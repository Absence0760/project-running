import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/food_search.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/widgets/nutrition_log_sheet.dart';

Future<({LocalFoodStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('nutrition_log_$tag');
  final store = LocalFoodStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

/// A store whose create throws, to drive the save-failure path.
class _ThrowingFoodStore extends LocalFoodStore {
  @override
  Future<StoredFood> createLocal({
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool isPublic = false,
  }) async {
    throw StateError('disk write failed');
  }
}

Widget _host(LocalFoodStore store, {FoodFetcher? fetcher}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: NutritionLogSheet(store: store, fetcher: fetcher)),
    );

const _sample = {
  'products': [
    {
      'code': '111',
      'product_name': 'Rolled Oats',
      'nutriments': {
        'energy-kcal_100g': 389,
        'proteins_100g': 16.9,
      },
    },
  ],
};

void main() {
  testWidgets('manual entry logs a food item to the store', (tester) async {
    final f = await _store('manual_');
    try {
      await tester.pumpWidget(_host(f.store));
      await tester.pump();
      await tester.tap(find.text('Enter manually'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, ''); // focus
      // Item name is the first TextField inside the manual block; simplest is
      // to target by its label text field — fill name + calories.
      await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Banana');
      await tester.enterText(find.widgetWithText(TextField, 'Calories'), '105');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(f.store.rows, hasLength(1));
      final e = f.store.rows.first;
      expect(e['item_name'], 'Banana');
      expect(e['meal_slot'], 'breakfast');
      expect(e['calories'], 105.0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('search renders Open Food Facts results via the injected fetcher',
      (tester) async {
    final f = await _store('search_');
    try {
      await tester.pumpWidget(_host(f.store, fetcher: (u) async {
        return jsonEncode(_sample);
      }));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search for a food'), 'oats');
      // Debounce (350ms) then the async search resolves.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('Rolled Oats'), findsOneWidget);
      expect(find.textContaining('389 kcal / 100 g'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a failed save surfaces an error and keeps the sheet open',
      (tester) async {
    await tester.pumpWidget(_host(_ThrowingFoodStore()));
    await tester.pump();
    await tester.tap(find.text('Enter manually'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Banana');
    await tester.enterText(find.widgetWithText(TextField, 'Calories'), '105');
    await tester.pump();
    await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Error banner shows; the sheet stays open (still find the form fields).
    expect(find.text("Couldn't log food. Try again."), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Item name'), findsOneWidget);
  });
}
