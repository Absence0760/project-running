import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/nutrition_targets.dart';
import '../lib/nutrition_totals.dart';
import '../lib/widgets/nutrition_rings_card.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {double textScale = 1.0}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
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

    testWidgets('a ceiling macro over target shows the +overage badge', (tester) async {
      // Calories well over the 2550 ceiling → recoloured ring with "+overage".
      const over = MacroTotals(calories: 2800, proteinG: 132, carbsG: 180, fatG: 61);
      await _pump(
        tester,
        const NutritionRingsCard(consumed: over, targets: targets, onTap: _noop),
      );
      // 2800 − 2550 = 250 over the calorie ceiling.
      expect(find.text('+250'), findsOneWidget);
      // The raw calorie number is replaced by the overage badge.
      expect(find.text('2800'), findsNothing);
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

    testWidgets('the ring value stays inside the 48 px arc at 2x text scale',
        (tester) async {
      // A four-digit calorie count already fills 46 of the 48 px at 1.0x; at
      // 2x it needed 90 and was wrapped and cropped inside the ring.
      const big =
          MacroTotals(calories: 2450, proteinG: 132, carbsG: 180, fatG: 61);
      final value = find.ancestor(
          of: find.text('2450'), matching: find.byType(FittedBox));

      await _pump(
        tester,
        const NutritionRingsCard(consumed: big, targets: null, onTap: _noop),
      );
      final at1x = tester.getSize(value.first);

      await _pump(
        tester,
        const NutritionRingsCard(consumed: big, targets: null, onTap: _noop),
        textScale: 2.0,
      );
      final at2x = tester.getSize(value.first);
      expect(at2x.width, lessThanOrEqualTo(48));
      expect(at2x.height, lessThanOrEqualTo(48));
      expect(at2x.width, greaterThanOrEqualTo(at1x.width));
    });
  });
}

void _noop() {}
