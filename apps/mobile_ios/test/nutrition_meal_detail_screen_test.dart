import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/screens/nutrition_meal_detail_screen.dart';

Future<({LocalFoodStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('meal_detail_$tag');
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

  testWidgets('shows the slot title, macro total, items, and trend',
      (tester) async {
    final f = await _store('items_');
    final today = DateTime.now();
    await tester.runAsync(() async {
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 8),
        itemName: 'Oats',
        mealSlot: 'breakfast',
        calories: 300,
        proteinG: 12,
      );
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 9),
        itemName: 'Berries',
        mealSlot: 'breakfast',
        calories: 80,
      );
      // A lunch item that must NOT appear in the breakfast detail.
      await f.store.createLocal(
        startedAt: DateTime(today.year, today.month, today.day, 12),
        itemName: 'Sandwich',
        mealSlot: 'lunch',
        calories: 500,
      );
    });
    try {
      await tester.pumpWidget(_app(f.store, today, 'breakfast'));
      await tester.pump();
      // Slot title (AppBar) + the two breakfast items, not the lunch one.
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Berries'), findsOneWidget);
      expect(find.text('Sandwich'), findsNothing);
      // Macro total = 300 + 80 = 380 kcal (appears in the macro card and, for
      // today, as the trend bar's label too).
      expect(find.text('380'), findsWidgets);
      // Protein total surfaces in the macro breakdown.
      expect(find.text('12g'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('shows the empty-items state for a slot with nothing logged',
      (tester) async {
    final f = await _store('empty_');
    try {
      await tester.pumpWidget(_app(f.store, DateTime.now(), 'dinner'));
      await tester.pump();
      expect(find.text('Nothing logged for this meal.'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
