import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/badges.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/badge_grid.dart';

AchievementRow _award({
  String badgeKey = 'streak',
  String tier = 'gold',
  bool isPublic = true,
}) =>
    AchievementRow(
      id: '$badgeKey-$tier',
      userId: 'u1',
      badgeKey: badgeKey,
      tier: tier,
      sourceKind: 'streak',
      earnedAt: DateTime.utc(2026, 5, 1, 12),
      isPublic: isPublic,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => initializeDateFormatting());

  testWidgets('empty owner state renders the keep-running prompt',
      (tester) async {
    await tester.pumpWidget(_host(const BadgeGrid(badges: [], isOwner: true)));
    expect(find.text('No badges yet — keep running.'), findsOneWidget);
  });

  testWidgets('empty non-owner state renders the public-empty prompt',
      (tester) async {
    await tester.pumpWidget(_host(const BadgeGrid(badges: [], isOwner: false)));
    expect(find.text('No public badges yet.'), findsOneWidget);
  });

  testWidgets('a seeded award renders its label, tier and earned date',
      (tester) async {
    await tester.pumpWidget(_host(BadgeGrid(badges: [_award()])));
    await tester.pump();
    expect(find.text('Century streak'), findsOneWidget);
    expect(find.text('GOLD'), findsOneWidget);
    expect(find.textContaining('Earned'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
  });

  test('badgeLabelFor resolves a stored award to its catalogue label', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(badgeLabelFor(l10n, 'pr', 'gold'), 'PR collector');
    expect(badgeLabelFor(l10n, 'unknown', 'gold'), 'unknown');
  });

  test('badgeIconData maps every catalogue icon to a real IconData', () {
    for (final b in kBadgeCatalogue) {
      for (final t in b.tiers) {
        expect(badgeIconData(t.icon), isA<IconData>());
      }
    }
  });

  test('badgeTierColor + badgeTierLabel cover all tiers', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final tier in kTierOrder) {
      expect(badgeTierColor(tier), isA<Color>());
      expect(badgeTierLabel(l10n, tier), isNotEmpty);
    }
  });
}
