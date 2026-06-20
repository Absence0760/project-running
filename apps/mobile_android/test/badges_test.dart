import 'package:flutter_test/flutter_test.dart';

import '../lib/badges.dart';

EarnedBadge? _find(BadgeInput input, String badgeKey) {
  for (final e in evaluateBadges(input)) {
    if (e.badgeKey == badgeKey) return e;
  }
  return null;
}

void main() {
  test('no milestones -> no badges', () {
    expect(evaluateBadges(const BadgeInput()), isEmpty);
  });

  test('catalogue ids are unique and tiers ascend by threshold', () {
    final ids = <String>{};
    for (final b in kBadgeCatalogue) {
      expect(ids.contains(b.id), isFalse, reason: 'duplicate id ${b.id}');
      ids.add(b.id);
      for (var i = 1; i < b.tiers.length; i++) {
        expect(b.tiers[i].threshold > b.tiers[i - 1].threshold, isTrue,
            reason: '${b.id} tiers not ascending');
        expect(
            kTierOrder.indexOf(b.tiers[i].tier) >
                kTierOrder.indexOf(b.tiers[i - 1].tier),
            isTrue,
            reason: '${b.id} tier order wrong');
      }
    }
  });

  test('single-run distance: 5k earns bronze, exact boundary inclusive', () {
    final e = _find(const BadgeInput(longestRunM: 5000), 'distance_single');
    expect(e?.tier, 'bronze');
    expect(e?.valueNum, 5000);
  });

  test('single-run distance: just under 5k earns nothing', () {
    expect(_find(const BadgeInput(longestRunM: 4999), 'distance_single'), isNull);
  });

  test('single-run distance: marathon earns gold, not also bronze/silver', () {
    final single = evaluateBadges(const BadgeInput(longestRunM: 42195))
        .where((e) => e.badgeKey == 'distance_single')
        .toList();
    expect(single.length, 1);
    expect(single[0].tier, 'gold');
  });

  test('single-run distance: 50k+ earns platinum (ultra)', () {
    expect(_find(const BadgeInput(longestRunM: 60000), 'distance_single')?.tier,
        'platinum');
  });

  test('lifetime distance: 100km bronze, 1000km gold', () {
    expect(_find(const BadgeInput(lifetimeDistanceM: 100000), 'distance_lifetime')?.tier,
        'bronze');
    expect(_find(const BadgeInput(lifetimeDistanceM: 1000000), 'distance_lifetime')?.tier,
        'gold');
  });

  test('lifetime distance: 5000km platinum is the cap', () {
    expect(_find(const BadgeInput(lifetimeDistanceM: 9000000), 'distance_lifetime')?.tier,
        'platinum');
  });

  test('streak: 7 days bronze, 30 silver, 100 gold, 365 platinum', () {
    expect(_find(const BadgeInput(bestStreakDays: 7), 'streak')?.tier, 'bronze');
    expect(_find(const BadgeInput(bestStreakDays: 30), 'streak')?.tier, 'silver');
    expect(_find(const BadgeInput(bestStreakDays: 100), 'streak')?.tier, 'gold');
    expect(_find(const BadgeInput(bestStreakDays: 365), 'streak')?.tier, 'platinum');
  });

  test('streak: 6 days earns nothing', () {
    expect(_find(const BadgeInput(bestStreakDays: 6), 'streak'), isNull);
  });

  test('pr: first PR bronze, 3 silver, all-5 gold', () {
    expect(_find(const BadgeInput(prCount: 1), 'pr')?.tier, 'bronze');
    expect(_find(const BadgeInput(prCount: 3), 'pr')?.tier, 'silver');
    expect(_find(const BadgeInput(prCount: 5), 'pr')?.tier, 'gold');
  });

  test('plan finisher: 1 bronze, 3 silver, 10 gold', () {
    expect(_find(const BadgeInput(completedPlanCount: 1), 'plan_finisher')?.tier, 'bronze');
    expect(_find(const BadgeInput(completedPlanCount: 3), 'plan_finisher')?.tier, 'silver');
    expect(_find(const BadgeInput(completedPlanCount: 10), 'plan_finisher')?.tier, 'gold');
  });

  test('a maxed-out user earns one badge per family at the top tier', () {
    final all = evaluateBadges(const BadgeInput(
      longestRunM: 100000,
      lifetimeDistanceM: 6000000,
      bestStreakDays: 400,
      prCount: 5,
      completedPlanCount: 12,
    ));
    expect(all.length, kBadgeCatalogue.length);
    for (final b in kBadgeCatalogue) {
      expect(all.where((x) => x.badgeKey == b.id).length, 1,
          reason: '${b.id} should appear once');
    }
    expect(all.firstWhere((e) => e.badgeKey == 'distance_single').tier, 'platinum');
    expect(all.firstWhere((e) => e.badgeKey == 'pr').tier, 'gold');
  });

  test('output order follows catalogue order', () {
    final all = evaluateBadges(const BadgeInput(
      longestRunM: 5000,
      lifetimeDistanceM: 100000,
      bestStreakDays: 7,
      prCount: 1,
      completedPlanCount: 1,
    ));
    expect(all.map((e) => e.badgeKey).toList(),
        kBadgeCatalogue.map((b) => b.id).toList());
  });

  test('tierFor resolves a stored award to its catalogue tier', () {
    expect(tierFor('streak', 'gold')?.threshold, 100);
    expect(tierFor('nope', 'bronze'), isNull);
    expect(tierFor('streak', 'platinum')?.threshold, 365);
  });
}
