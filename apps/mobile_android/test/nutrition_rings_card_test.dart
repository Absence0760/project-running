import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/nutrition_targets.dart';
import '../lib/nutrition_totals.dart';
import '../lib/widgets/nutrition_rings_card.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  const consumed =
      MacroTotals(calories: 1840, proteinG: 132, carbsG: 180, fatG: 61);
  const targets = NutritionTargets(
      calories: 2550,
      baseCalories: 2550,
      exerciseKcal: 0,
      proteinG: 165,
      carbsG: 280,
      fatG: 85);

  group('NutritionRingsCard', () {
    testWidgets('renders four macro rings + the kcal value', (tester) async {
      await _pump(
        tester,
        const NutritionRingsCard(
            consumed: consumed, targets: targets, onTap: _noop),
      );
      expect(find.byType(CircularProgressIndicator), findsNWidgets(4));
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('1840'), findsOneWidget);
    });

    testWidgets('renders unfilled rings when targets are absent', (tester) async {
      await _pump(
        tester,
        const NutritionRingsCard(
            consumed: consumed, targets: null, onTap: _noop),
      );
      // Still four rings, still the consumed numbers — no zeroed target shown.
      expect(find.byType(CircularProgressIndicator), findsNWidgets(4));
      expect(find.text('1840'), findsOneWidget);
    });

    testWidgets('tapping invokes onTap', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        NutritionRingsCard(
            consumed: consumed, targets: targets, onTap: () => tapped = true),
      );
      await tester.tap(find.byType(NutritionRingsCard));
      expect(tapped, isTrue);
    });
  });
}

void _noop() {}
