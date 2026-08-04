import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/screens/settings_body_metrics_screen.dart';

class _OfflineFakeApi extends ApiClient {
  @override
  String? get userId => null;
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final Directory _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp.path;
  @override
  Future<String?> getApplicationSupportPath() async => _tmp.path;
  @override
  Future<String?> getTemporaryPath() async => _tmp.path;
}

class _ThrowingDeleteFoodStore extends LocalFoodStore {
  @override
  Future<void> deleteLocal(String id) async {
    throw StateError('disk full');
  }
}

Future<({LocalFoodStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('nutrition_screen_$tag');
  final store = LocalFoodStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

/// Real file I/O driven from a tap has no completion hook to await, so poll
/// the observable end-state rather than sleeping a fixed duration — a fixed
/// wait races a loaded CI runner, which then tears the temp dir down while
/// the write is still in flight (CI run 29517668370).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after $timeout waiting for the expected state');
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Widget _app(LocalFoodStore store) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NutritionScreen(api: _OfflineFakeApi(), store: store),
    );

void main() {
  group('exerciseInputsForDay', _exerciseInputsTests);

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

  testWidgets('targets-unset state offers a route to Body metrics, not the web',
      (tester) async {
    // The copy used to tell mobile users to go and fill their body metrics
    // in on the WEB app, three taps after SettingsBodyMetricsScreen shipped
    // here. The empty state is now the way in.
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    final f = await _store('targets_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(
        find.text(
            'Add your height, weight, age and sex to see calorie + macro targets.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add body metrics'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsBodyMetricsScreen), findsOneWidget);
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
      });
      await _pumpUntil(tester, () => f.store.rows.isEmpty);
      await tester.pumpAndSettle();

      expect(find.text('Oats'), findsNothing);
      expect(f.store.rows.length, 0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a failed entry delete surfaces an error banner', (tester) async {
    final dir =
        Directory.systemTemp.createTempSync('nutrition_screen_del_fail_');
    final store = _ThrowingDeleteFoodStore();
    await store.init(overrideDirectory: dir);
    await tester.runAsync(() => store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(store));
      await tester.pump();

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
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // The delete threw; the entry is still listed and an error banner shows
      // (rather than the failure being swallowed silently).
      expect(find.text('Oats'), findsOneWidget);
      expect(
        find.textContaining("Couldn’t delete the entry"),
        findsOneWidget,
      );
      // Drain the showTopBanner auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // #501: each autofocus name-entry dialog must release focus on dismissal so
  // a later plain delete confirmation (which has no text field) can't resurface
  // the soft keyboard. The keyboard resurface is a platform-IME behaviour the
  // widget-test harness can't simulate (focus restoration already moves primary
  // focus off the disposed TextField), so this source-level guard pins the fix
  // at its root — both dialogs unfocus after their showDialog await.
  test('#501: every autofocus name dialog unfocuses on dismissal', () {
    final src =
        File('lib/screens/nutrition_screen.dart').readAsStringSync();
    final autofocusCount = 'autofocus: true'.allMatches(src).length;
    final unfocusCount =
        'FocusManager.instance.primaryFocus?.unfocus();'.allMatches(src).length;
    expect(
      unfocusCount,
      greaterThanOrEqualTo(autofocusCount),
      reason:
          'each of the $autofocusCount autofocus TextField dialogs must release '
          'focus on dismissal (found $unfocusCount unfocus calls) — see #501',
    );
  });

  testWidgets('name dialog dismiss releases focus before the delete dialog',
      (tester) async {
    final f = await _store('focus_leak_');
    final pp = Directory.systemTemp.createTempSync('nutrition_focus_pp_');
    PathProviderPlatform.instance = _FakePathProvider(pp);
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();

      // Open the autofocus name-entry dialog — its TextField grabs focus and
      // raises the soft keyboard.
      await tester.tap(find.byTooltip('Save as meal'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(tester.testTextInput.isVisible, isTrue);

      // Cancel it. The fix unfocuses on dismissal.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<EditableText>()));

      // Now the plain delete confirmation must not bring the keyboard back.
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
    } finally {
      f.dir.deleteSync(recursive: true);
      pp.deleteSync(recursive: true);
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

  // Pins the in-flight double-submit guard on Save as meal: the AppBar
  // action disables while the create is running, so a second tap during the
  // write window can't fire a duplicate template.
  testWidgets('Save as meal disables while saving (no double-submit)',
      (tester) async {
    final f = await _store('save_meal_');
    final pp = Directory.systemTemp.createTempSync('nutrition_pp_');
    PathProviderPlatform.instance = _FakePathProvider(pp);
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();

      await tester.tap(find.byTooltip('Save as meal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My breakfast');

      // The whole save (createLocal file I/O after the confirm) is anchored to
      // the zone the confirm fires in, so it must run under runAsync.
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Save meal'),
      );
      await tester.runAsync(() async {
        await tester.tap(confirm);
      });
      await _pumpUntil(
          tester, () => find.text('My breakfast').evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      // Saved exactly once: the template section shows the one row, and the
      // save action is re-enabled (the guard released in `finally`).
      expect(find.text('My breakfast'), findsOneWidget);
      final saveBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
      );
      expect(saveBtn.onPressed, isNotNull);

      // Drain the showTopBanner auto-dismiss timer (mobile-test gotcha).
      await tester.pump(const Duration(seconds: 5));
    } finally {
      f.dir.deleteSync(recursive: true);
      pp.deleteSync(recursive: true);
    }
  });
}

/// The exercise add-on's day + kind selection, pulled out of the screen.
/// Regression: the filter compared against `'gym'`, a kind the `activities`
/// view never emits (its gym branch is `'lift'`), so every strength session
/// was dropped and contributed zero calories and zero hydration minutes.
void _exerciseInputsTests() {
  ActivityRow row(String kind, DateTime at, Map<String, dynamic> summary) =>
      ActivityRow(id: kind, kind: kind, startedAt: at, summary: summary);

  final start = DateTime(2026, 7, 24);
  final end = DateTime(2026, 7, 25);

  test('a gym workout counts toward the day, under its real kind', () {
    final day = exerciseInputsForDay([
      row(ActivityRow.kindLift, DateTime(2026, 7, 24, 18),
          {'duration_s': 3600}),
    ], start, end);

    expect(day.gym.length, 1);
    expect(day.gym.single.durationS, 3600);
    expect(day.seconds, 3600);
    expect(day.runs, isEmpty);
  });

  test("'gym' is not a kind the view emits and must not be matched", () {
    final day = exerciseInputsForDay(
      [row('gym', DateTime(2026, 7, 24, 18), {'duration_s': 3600})],
      start,
      end,
    );
    expect(day.gym, isEmpty);
    expect(day.seconds, 0);
  });

  test('runs carry distance, meals are ignored entirely', () {
    final day = exerciseInputsForDay([
      row(ActivityRow.kindRun, DateTime(2026, 7, 24, 7),
          {'duration_s': 1800, 'distance_m': 5000}),
      row(ActivityRow.kindMeal, DateTime(2026, 7, 24, 12), {'duration_s': 60}),
    ], start, end);

    expect(day.runs.single.distanceM, 5000);
    expect(day.gym, isEmpty);
    expect(day.seconds, 1800, reason: 'the meal must not add to the total');
  });

  test('the window is half-open — yesterday and tomorrow are excluded', () {
    final day = exerciseInputsForDay([
      row(ActivityRow.kindRun, DateTime(2026, 7, 23, 23, 59),
          {'duration_s': 600}),
      row(ActivityRow.kindLift, end, {'duration_s': 600}),
      row(ActivityRow.kindRun, DateTime(2026, 7, 24, 23, 59),
          {'duration_s': 600}),
    ], start, end);

    expect(day.seconds, 600);
    expect(day.runs.length, 1);
    expect(day.gym, isEmpty);
  });

  test('a missing duration contributes zero rather than throwing', () {
    final day = exerciseInputsForDay([
      row(ActivityRow.kindLift, DateTime(2026, 7, 24, 18), const {}),
    ], start, end);

    expect(day.gym.single.durationS, isNull);
    expect(day.seconds, 0);
  });

  test('the kind constants are the literals the activities view emits', () {
    // Ties the Dart names to the SQL so a renamed UNION branch fails here
    // instead of silently matching nothing at a call site.
    final sql = File(
      '../backend/supabase/migrations/'
      '20270413_001_activities_view_project_is_dnf.sql',
    ).readAsStringSync();
    for (final kind in [
      ActivityRow.kindRun,
      ActivityRow.kindLift,
      ActivityRow.kindMeal,
    ]) {
      expect(sql, contains("'$kind'::text as kind"), reason: kind);
    }
  });
}
