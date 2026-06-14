import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/screens/nutrition_meal_detail_screen.dart';

/// Deeper coverage for `nutrition_meal_detail_screen.dart` — the macro
/// aggregation across all four fields, the null-slot → snack folding, and the
/// trailing 7-day per-slot trend's slot + day isolation. Complements the two
/// happy-path tests in `nutrition_meal_detail_screen_test.dart`.
Future<({LocalFoodStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('meal_depth_$tag');
  final store = LocalFoodStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

Widget _app(LocalFoodStore store, DateTime day, String slot) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NutritionMealDetailScreen(store: store, day: day, slot: slot),
    );

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('macro card aggregates calories + all three macros across items',
      (tester) async {
    final f = await _store('macros_');
    final today = DateTime.now();
    await tester.runAsync(() async {
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 18),
        itemName: 'Chicken',
        mealSlot: 'dinner',
        calories: 400,
        proteinG: 40,
        carbsG: 0,
        fatG: 10,
      );
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 18, 30),
        itemName: 'Rice',
        mealSlot: 'dinner',
        calories: 250,
        proteinG: 5,
        carbsG: 55,
        fatG: 1,
      );
    });
    try {
      await tester.pumpWidget(_app(f.store, today, 'dinner'));
      await tester.pump();

      expect(find.text('Dinner'), findsOneWidget);
      // Σ calories = 650, protein = 45g, carbs = 55g, fat = 11g.
      expect(find.text('650'), findsWidgets); // macro card + today's trend bar
      expect(find.text('45g'), findsOneWidget);
      expect(find.text('55g'), findsOneWidget);
      expect(find.text('11g'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('an entry with a null meal slot folds into the snack detail',
      (tester) async {
    final f = await _store('snack_');
    final today = DateTime.now();
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime(today.year, today.month, today.day, 15),
          itemName: 'Almonds',
          // No mealSlot → defaults to snack on both the slot filter and trend.
          calories: 170,
        ));
    try {
      await tester.pumpWidget(_app(f.store, today, 'snack'));
      await tester.pump();

      expect(find.text('Snack'), findsOneWidget);
      expect(find.text('Almonds'), findsOneWidget);
      expect(find.text('170 kcal'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the 7-day trend isolates this slot and ignores other slots',
      (tester) async {
    final f = await _store('trend_slot_');
    final today = DateTime.now();
    await tester.runAsync(() async {
      // Today's lunch — the slot under view.
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 12),
        itemName: 'Salad',
        mealSlot: 'lunch',
        calories: 300,
      );
      // Same day, DIFFERENT slot — must not bleed into the lunch trend's
      // today bar (which would otherwise read 300 + 900 = 1200).
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 19),
        itemName: 'Pizza',
        mealSlot: 'dinner',
        calories: 900,
      );
    });
    try {
      await tester.pumpWidget(_app(f.store, today, 'lunch'));
      await tester.pump();

      expect(find.text('Last 7 days'), findsOneWidget);
      // Today's lunch trend bar reads 300, never the cross-slot 1200.
      expect(find.text('1200'), findsNothing);
      // 300 surfaces (macro card + the today trend bar label).
      expect(find.text('300'), findsWidgets);
      // The dinner item is not in the lunch item list.
      expect(find.text('Pizza'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a prior-day entry in the same slot lands on its own trend bar',
      (tester) async {
    // Two lunches two days apart — the trend must keep them on separate
    // day buckets (not collapse to one), so both calorie labels appear.
    final f = await _store('trend_day_');
    final today = DateTime.now();
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await tester.runAsync(() async {
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 12),
        itemName: 'Today lunch',
        mealSlot: 'lunch',
        calories: 420,
      );
      await f.store.createLocal(
        startedAt:
            DateTime(twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day, 12),
        itemName: 'Old lunch',
        mealSlot: 'lunch',
        calories: 510,
      );
    });
    try {
      await tester.pumpWidget(_app(f.store, today, 'lunch'));
      await tester.pump();

      // Both days' totals show as distinct trend-bar labels (and 420 also in
      // the macro card for today). The two-days-ago bar carries 510.
      expect(find.text('420'), findsWidgets);
      expect(find.text('510'), findsOneWidget);
      // Only today's item is in the items card.
      expect(find.text('Today lunch'), findsOneWidget);
      expect(find.text('Old lunch'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
