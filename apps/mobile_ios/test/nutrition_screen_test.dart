import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/screens/nutrition_screen.dart';

class _OfflineFakeApi extends ApiClient {
  @override
  String? get userId => null;
}

Future<({LocalFoodStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('nutrition_screen_$tag');
  final store = LocalFoodStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

Widget _app(LocalFoodStore store) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NutritionScreen(api: _OfflineFakeApi(), store: store),
    );

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the empty state when nothing is logged today',
      (tester) async {
    final f = await _store('empty_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(find.text('No food logged today'), findsOneWidget);
      // Rings + water cards still render with zeros.
      expect(find.text('Water'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a logged meal shows under its slot with calories',
      (tester) async {
    final f = await _store('list_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
          proteinG: 12,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      // 350 kcal shows twice: the calories ring centre + the meal-row value.
      expect(find.text('350'), findsNWidgets(2));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('deleting an entry asks to confirm; Cancel keeps it',
      (tester) async {
    final f = await _store('del_cancel_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(find.text('Oats'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Oats'), findsOneWidget);
      expect(f.store.rows.length, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('deleting an entry → confirm removes it', (tester) async {
    final f = await _store('del_confirm_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();

      // _delete (and the deleteLocal file I/O it awaits after the confirm)
      // is anchored to the zone the row tap fires in, so both taps run
      // under runAsync; real I/O only resolves there.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Delete'));
      });
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      );
      await tester.runAsync(() async {
        await tester.tap(confirm);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Oats'), findsNothing);
      expect(f.store.rows.length, 0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('water card shows the litre readout + a remaining chip',
      (tester) async {
    final f = await _store('water_target_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      // Offline (no body weight) → flat 2 L goal, nothing drunk yet.
      expect(find.text('0 / 2 L'), findsOneWidget);
      expect(find.text('2000 ml left'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('water tracker increments by a 250 ml unit', (tester) async {
    final f = await _store('water_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(find.text('0 × 250 ml'), findsOneWidget);
      await tester.tap(find.byTooltip('Add water'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('1 × 250 ml'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
