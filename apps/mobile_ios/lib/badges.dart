/// Achievement badge catalogue — defined as code, the guided-runs pattern.
///
/// The catalogue (the *definition* of every badge + tier + threshold) lives
/// here, not in the DB. The DB stores only awards (which user earned which
/// badge, when). This keeps the catalogue versionable/testable and avoids a
/// round-trip to know what badges exist.
///
/// [evaluateBadges] is a pure dispatcher: it takes the user's milestone
/// primitives (PR count, lifetime/single-run distance, best streak, completed
/// plan count) and returns the earned set with the highest tier reached per
/// family. The SQL `award_achievements_for_user` function duplicates these
/// exact thresholds; `badges_test.dart` (mobile) + `badges.test.ts` (web) +
/// `achievements_test.sql` (pgtap) pin the contract so drift fails CI.
///
/// Labels/descriptions are NOT stored on the catalogue entries — only their
/// i18n keys (the camelCase ARB keys). The display layer resolves
/// [BadgeTier.labelKey]/[BadgeTier.descKey] via `AppLocalizations` so the grid
/// re-renders on locale switch.
///
/// Mirrors `apps/web/src/lib/social/badges.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair.

/// Tier order, low to high. The earned tier is the highest threshold met.
const List<String> kTierOrder = ['bronze', 'silver', 'gold', 'platinum'];

class BadgeTier {
  final String tier;

  /// Numeric threshold in the family's native unit (metres / days / count).
  final double threshold;

  /// Material Symbols ligature name (mapped to an [IconData] at display time).
  final String icon;
  final String labelKey;
  final String descKey;

  const BadgeTier({
    required this.tier,
    required this.threshold,
    required this.icon,
    required this.labelKey,
    required this.descKey,
  });
}

class Badge {
  /// Stable catalogue id, matches the DB `badge_key`.
  final String id;
  final String sourceKind;

  /// Ordered low to high; [evaluateBadges] returns the highest tier met.
  final List<BadgeTier> tiers;

  const Badge({
    required this.id,
    required this.sourceKind,
    required this.tiers,
  });
}

/// The numeric the user fed in that earned the tier (display + DB dedupe).
class EarnedBadge {
  final String badgeKey;
  final String sourceKind;
  final String tier;
  final double threshold;
  final String icon;
  final String labelKey;
  final String descKey;

  /// The user's actual value that cleared the threshold.
  final double valueNum;

  const EarnedBadge({
    required this.badgeKey,
    required this.sourceKind,
    required this.tier,
    required this.threshold,
    required this.icon,
    required this.labelKey,
    required this.descKey,
    required this.valueNum,
  });
}

/// Primitives the catalogue evaluates. All non-negative; absent maps to 0.
class BadgeInput {
  /// Best single-run distance in metres (longest run).
  final double longestRunM;

  /// Lifetime summed distance in metres.
  final double lifetimeDistanceM;

  /// Best run streak in days.
  final double bestStreakDays;

  /// Count of distinct PR distances held (0-5: 5k/10k/half/marathon/mile).
  final double prCount;

  /// Count of completed training plans.
  final double completedPlanCount;

  const BadgeInput({
    this.longestRunM = 0,
    this.lifetimeDistanceM = 0,
    this.bestStreakDays = 0,
    this.prCount = 0,
    this.completedPlanCount = 0,
  });
}

/// The catalogue. Thresholds are the lockstep contract with the SQL award
/// function — if you change a number here, change it in
/// `20270208_001_achievements.sql` too (the pgtap pins it).
const List<Badge> kBadgeCatalogue = [
  Badge(
    id: 'distance_single',
    sourceKind: 'distance',
    tiers: [
      BadgeTier(tier: 'bronze', threshold: 5000, icon: 'directions_run', labelKey: 'badgesDistanceSingle5kLabel', descKey: 'badgesDistanceSingle5kDesc'),
      BadgeTier(tier: 'silver', threshold: 21097, icon: 'military_tech', labelKey: 'badgesDistanceSingleHalfLabel', descKey: 'badgesDistanceSingleHalfDesc'),
      BadgeTier(tier: 'gold', threshold: 42195, icon: 'military_tech', labelKey: 'badgesDistanceSingleMarathonLabel', descKey: 'badgesDistanceSingleMarathonDesc'),
      BadgeTier(tier: 'platinum', threshold: 50000, icon: 'workspace_premium', labelKey: 'badgesDistanceSingleUltraLabel', descKey: 'badgesDistanceSingleUltraDesc'),
    ],
  ),
  Badge(
    id: 'distance_lifetime',
    sourceKind: 'distance',
    tiers: [
      BadgeTier(tier: 'bronze', threshold: 100000, icon: 'route', labelKey: 'badgesDistanceLifetime100Label', descKey: 'badgesDistanceLifetime100Desc'),
      BadgeTier(tier: 'silver', threshold: 500000, icon: 'route', labelKey: 'badgesDistanceLifetime500Label', descKey: 'badgesDistanceLifetime500Desc'),
      BadgeTier(tier: 'gold', threshold: 1000000, icon: 'public', labelKey: 'badgesDistanceLifetime1000Label', descKey: 'badgesDistanceLifetime1000Desc'),
      BadgeTier(tier: 'platinum', threshold: 5000000, icon: 'public', labelKey: 'badgesDistanceLifetime5000Label', descKey: 'badgesDistanceLifetime5000Desc'),
    ],
  ),
  Badge(
    id: 'streak',
    sourceKind: 'streak',
    tiers: [
      BadgeTier(tier: 'bronze', threshold: 7, icon: 'local_fire_department', labelKey: 'badgesStreak7Label', descKey: 'badgesStreak7Desc'),
      BadgeTier(tier: 'silver', threshold: 30, icon: 'local_fire_department', labelKey: 'badgesStreak30Label', descKey: 'badgesStreak30Desc'),
      BadgeTier(tier: 'gold', threshold: 100, icon: 'local_fire_department', labelKey: 'badgesStreak100Label', descKey: 'badgesStreak100Desc'),
      BadgeTier(tier: 'platinum', threshold: 365, icon: 'whatshot', labelKey: 'badgesStreak365Label', descKey: 'badgesStreak365Desc'),
    ],
  ),
  Badge(
    id: 'pr',
    sourceKind: 'pr',
    tiers: [
      BadgeTier(tier: 'bronze', threshold: 1, icon: 'timer', labelKey: 'badgesPr1Label', descKey: 'badgesPr1Desc'),
      BadgeTier(tier: 'silver', threshold: 3, icon: 'timer', labelKey: 'badgesPr3Label', descKey: 'badgesPr3Desc'),
      BadgeTier(tier: 'gold', threshold: 5, icon: 'trophy', labelKey: 'badgesPr5Label', descKey: 'badgesPr5Desc'),
    ],
  ),
  Badge(
    id: 'plan_finisher',
    sourceKind: 'plan',
    tiers: [
      BadgeTier(tier: 'bronze', threshold: 1, icon: 'flag', labelKey: 'badgesPlan1Label', descKey: 'badgesPlan1Desc'),
      BadgeTier(tier: 'silver', threshold: 3, icon: 'flag', labelKey: 'badgesPlan3Label', descKey: 'badgesPlan3Desc'),
      BadgeTier(tier: 'gold', threshold: 10, icon: 'emoji_events', labelKey: 'badgesPlan10Label', descKey: 'badgesPlan10Desc'),
    ],
  ),
];

double _valueForBadge(Badge badge, BadgeInput input) {
  switch (badge.id) {
    case 'distance_single':
      return input.longestRunM;
    case 'distance_lifetime':
      return input.lifetimeDistanceM;
    case 'streak':
      return input.bestStreakDays;
    case 'pr':
      return input.prCount;
    case 'plan_finisher':
      return input.completedPlanCount;
    default:
      return 0;
  }
}

/// Pure dispatcher. Returns at most one [EarnedBadge] per catalogue family —
/// the highest tier whose threshold the user's value clears. A user at gold
/// does NOT also earn bronze/silver of the same family (one tile per family,
/// highest tier wins).
///
/// Deterministic + side-effect-free so it is unit-testable and matches the
/// SQL award function. Output order follows [kBadgeCatalogue] order.
List<EarnedBadge> evaluateBadges(BadgeInput input) {
  final out = <EarnedBadge>[];
  for (final badge in kBadgeCatalogue) {
    final value = _valueForBadge(badge, input);
    BadgeTier? earned;
    for (final t in badge.tiers) {
      if (value >= t.threshold) earned = t;
    }
    if (earned != null) {
      out.add(EarnedBadge(
        badgeKey: badge.id,
        sourceKind: badge.sourceKind,
        tier: earned.tier,
        threshold: earned.threshold,
        icon: earned.icon,
        labelKey: earned.labelKey,
        descKey: earned.descKey,
        valueNum: value,
      ));
    }
  }
  return out;
}

/// Resolve a catalogue entry's tier definition from a stored award.
BadgeTier? tierFor(String badgeKey, String tier) {
  for (final b in kBadgeCatalogue) {
    if (b.id != badgeKey) continue;
    for (final t in b.tiers) {
      if (t.tier == tier) return t;
    }
    return null;
  }
  return null;
}
