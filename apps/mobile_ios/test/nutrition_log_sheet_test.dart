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

Widget _host(
  LocalFoodStore store, {
  FoodFetcher? fetcher,
  BarcodeScanner? scanner,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: NutritionLogSheet(
          store: store,
          fetcher: fetcher,
          scanner: scanner,
        ),
      ),
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

  testWidgets('a failed search shows a retry state, not a misleading "no matches"',
      (tester) async {
    final f = await _store('search_fail_');
    try {
      var failNext = true;
      await tester.pumpWidget(_host(f.store, fetcher: (u) async {
        if (failNext) throw const SocketException('network down');
        return '{"products": []}';
      }));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search for a food'), 'oats');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      // The distinct failure copy + retry button — NOT the no-results state.
      expect(find.textContaining('Search failed'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry search'), findsOneWidget);
      expect(find.text('No matches. Try another term or enter it manually below.'),
          findsNothing);

      // Retry after recovery resolves to the genuine empty state.
      failNext = false;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry search'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.textContaining('Search failed'), findsNothing);
      expect(find.text('No matches. Try another term or enter it manually below.'),
          findsOneWidget);
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

  testWidgets('a scanned barcode that matches opens the confirm-portion dialog',
      (tester) async {
    final f = await _store('scan_match_');
    try {
      await tester.pumpWidget(_host(
        f.store,
        // The product-by-barcode lookup response shape ({status, product}).
        fetcher: (u) async => jsonEncode(const {
          'status': 1,
          'product': {
            'code': '737628064502',
            'product_name': 'Rolled Oats',
            'nutriments': {'energy-kcal_100g': 389},
          },
        }),
        scanner: (_) async => '737628064502',
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('Scan barcode'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      // The portion dialog opened on the matched product.
      expect(find.text('Rolled Oats'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Portion (g)'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a scanned barcode with no match shows the not-found message',
      (tester) async {
    final f = await _store('scan_nomatch_');
    try {
      await tester.pumpWidget(_host(
        f.store,
        fetcher: (u) async => '{"status": 0}',
        scanner: (_) async => '000000000000',
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('Scan barcode'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.textContaining('No product found'), findsOneWidget);
      // The manual / search fallback is still present.
      expect(find.text('Enter manually'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a scan lookup failure shows the distinct scan-failed message',
      (tester) async {
    final f = await _store('scan_fail_');
    try {
      await tester.pumpWidget(_host(
        f.store,
        fetcher: (u) async => throw const SocketException('network down'),
        scanner: (_) async => '737628064502',
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('Scan barcode'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.textContaining('Scan failed'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a cancelled scan does nothing and leaves the composer untouched',
      (tester) async {
    final f = await _store('scan_cancel_');
    try {
      await tester.pumpWidget(_host(f.store, scanner: (_) async => null));
      await tester.pump();
      await tester.tap(find.byTooltip('Scan barcode'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.textContaining('No product found'), findsNothing);
      expect(find.textContaining('Scan failed'), findsNothing);
      expect(f.store.rows, isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
