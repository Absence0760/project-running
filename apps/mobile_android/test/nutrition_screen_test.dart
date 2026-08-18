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
import '../lib/widgets/nutrition_log_sheet.dart';
import '../lib/widgets/undo_bar.dart';

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

/// Close the armed undo window so the deferred commit runs. The delete tap
/// itself must NOT be wrapped in `runAsync` any more — deferring means no store
/// I/O happens at tap time, and a timer armed in the real zone could not be
/// advanced by `pump` at all.
Future<void> _closeUndoWindow(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

Widget _app(LocalFoodStore store, {double textScale = 1.0}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: NutritionScreen(api: _OfflineFakeApi(), store: store),
    );

void main() {
  group('exerciseInputsForDay', _exerciseInputsTests);
  group('diary day navigation', _diaryDayTests);

  setUpAll(() => initializeDateFormatting());
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(debugResetUndo);

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

  // Issue #666 U8, mobile half: the food entry is the app's most frequently
  // deleted row and is re-typed in seconds, so it dropped its confirm for a
  // deferred, undoable delete (decisions § 514). These three tests replace the
  // confirm / cancel / confirm-then-remove trio that pinned the old shape.
  testWidgets('deleting an entry offers Undo and does NOT touch the store',
      (tester) async {
    final f = await _store('del_defer_');
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
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'confirm and undo are alternatives, not partners');
      expect(find.text('Oats'), findsNothing, reason: 'it leaves the list now');
      expect(find.text('Oats removed'), findsOneWidget);
      expect(f.store.rows.length, 1,
          reason: 'nothing is destroyed while undo is on offer');
      await _closeUndoWindow(tester);
      await _pumpUntil(tester, () => f.store.rows.isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('Undo puts the entry back with its stored row untouched',
      (tester) async {
    final f = await _store('del_undo_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    final before = Map<String, dynamic>.from(f.store.rows.single);
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(find.text('Oats'), findsOneWidget);
      expect(f.store.rows.single, before,
          reason: 'the row comes back byte-identical — it never left');
      // The window is cancelled, so no timer is left to drain.
      await tester.pump(const Duration(seconds: 9));
      expect(f.store.rows.length, 1);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the window closing commits the delete for real', (tester) async {
    final f = await _store('del_commit_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: DateTime.now(),
          itemName: 'Oats',
          mealSlot: 'breakfast',
          calories: 350,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await _closeUndoWindow(tester);
      await _pumpUntil(tester, () => f.store.rows.isEmpty);
      expect(find.text('Oats'), findsNothing);
      expect(f.store.rows.length, 0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a failed commit restores the entry and surfaces a banner',
      (tester) async {
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

      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(find.text('Oats'), findsNothing);

      // Let the window close so the commit runs and throws.
      await _closeUndoWindow(tester);
      await tester.pump();

      // A list must never claim a row is gone while the store still holds it.
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

  testWidgets('name dialog dismiss releases focus before the delete affordance',
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

      // Now the delete interaction must not bring the keyboard back. It is an
      // undo pill rather than a confirm dialog since round 13, but the
      // property this test exists for is unchanged: the field-less surface
      // that follows a dismissed name dialog must not resurface the IME.
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(find.text('Oats removed'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      // Drain the Restored banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
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
      // The guard now releases only once the write actually lands, so wait for
      // the persisted row AND the re-enable. `find.text` also matches the
      // dialog's own EditableText, so polling the typed name alone passes
      // before the save has even started.
      IconButton saveBtn() => tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
          );
      final templateDir = Directory('${pp.path}/meal_templates');
      await _pumpUntil(
          tester,
          () =>
              templateDir.existsSync() &&
              templateDir
                  .listSync()
                  .whereType<File>()
                  .any((e) =>
                      e.path.endsWith('.json') &&
                      !e.path.endsWith('index.json')) &&
              saveBtn().onPressed != null);
      await tester.pumpAndSettle();

      // Saved exactly once: the template section shows the one row, and the
      // save action is re-enabled (the guard released in `finally`).
      expect(find.text('My breakfast'), findsOneWidget);
      expect(saveBtn().onPressed, isNotNull);

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

  testWidgets(
      'the macro-ring value stays inside the 56 px arc at 2x text scale '
      '(issue #666 V12)', (tester) async {
    final f = await _store('ringscale_');
    await tester.runAsync(() async {
      await f.store.createLocal(
        startedAt: DateTime.now(),
        itemName: 'Big day',
        mealSlot: 'dinner',
        calories: 2450,
      );
    });
    try {
      final value = find.ancestor(
          of: find.text('2450'), matching: find.byType(FittedBox));

      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      final at1x = tester.getSize(value.first);

      await tester.pumpWidget(_app(f.store, textScale: 2.0));
      await tester.pump();
      // Pre-fix a four-digit calorie count needed 98 px inside the 56 px ring
      // and was wrapped and cropped there.
      final at2x = tester.getSize(value.first);
      expect(at2x.width, lessThanOrEqualTo(56));
      expect(at2x.height, lessThanOrEqualTo(56));
      expect(at2x.width, greaterThanOrEqualTo(at1x.width));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
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

/// The `?date=` day stepper web `/nutrition` gained on 2026-08-13, mirrored.
/// The load-bearing half is that back-filled logging stamps the VIEWED day —
/// a stepper that lets a runner review yesterday but silently logs to today
/// would be worse than no stepper at all.
void _diaryDayTests() {
  DateTime yesterdayNoon() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - 1, 12);
  }

  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  testWidgets('today cannot step forward and shows no back-fill hint',
      (tester) async {
    final f = await _store('day_today_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Anything you log here is added to this day.'),
          findsNothing);
      final next = tester.widget<IconButton>(find.ancestor(
          of: find.byTooltip('Next day'), matching: find.byType(IconButton)));
      expect(next.onPressed, isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('stepping back shows yesterday, its entries, and the hint',
      (tester) async {
    final f = await _store('day_back_');
    await tester.runAsync(() => f.store.createLocal(
          startedAt: yesterdayNoon(),
          itemName: 'Leftovers',
          mealSlot: 'dinner',
          calories: 700,
        ));
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
      expect(find.text('Leftovers'), findsNothing);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Leftovers'), findsOneWidget);
      expect(find.text('Oats'), findsNothing);
      expect(find.text('Anything you log here is added to this day.'),
          findsOneWidget);
      final next = tester.widget<IconButton>(find.ancestor(
          of: find.byTooltip('Next day'), matching: find.byType(IconButton)));
      expect(next.onPressed, isNotNull);

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Leftovers'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a past day with nothing logged says so, not "no food today"',
      (tester) async {
    final f = await _store('day_empty_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Nothing logged on this day.'), findsOneWidget);
      expect(find.text('No food logged today'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the water count is per viewed day, not one shared counter',
      (tester) async {
    final f = await _store('day_water_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Add water'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('1 × 250 ml'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('0 × 250 ml'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the composer opened on a past day is titled with that day',
      (tester) async {
    final f = await _store('day_sheet_');
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      await tester.tap(find.byTooltip('Log food'));
      await tester.pumpAndSettle();
      expect(find.byType(NutritionLogSheet), findsOneWidget);
      // Not the plain "Log food" title the today path uses.
      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Log food')),
        findsNothing,
      );
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  // The pre-existing bug this pins (followups, 2026-08-18): `initState` called
  // `loadAll()` instead of `init()`, so both owned stores had a null `dir` and
  // every save died on `dir!`. The row still landed in `rowsById`, so a test
  // asserting `find.text('My breakfast')` went green over a save that reached
  // neither disk nor the server. Assert the DISK, not the list.
  testWidgets('Save as meal persists the template to disk, not just memory',
      (tester) async {
    final f = await _store('save_meal_disk_');
    final pp = Directory.systemTemp.createTempSync('nutrition_disk_pp_');
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
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Save meal'),
      );
      await tester.runAsync(() async {
        await tester.tap(confirm);
      });
      // Poll the DISK, not the list: the row is installed in memory (and so
      // renders) before `writeJsonAtomic` renames its `.tmp` sibling into
      // place, which is exactly why a list assertion proves nothing here.
      final templateDir = Directory('${pp.path}/meal_templates');
      List<String> writtenRows() => templateDir.existsSync()
          ? templateDir
              .listSync()
              .whereType<File>()
              .where((e) =>
                  e.path.endsWith('.json') && !e.path.endsWith('index.json'))
              .map((e) => e.readAsStringSync())
              .toList()
          : <String>[];
      await _pumpUntil(tester, () => writtenRows().isNotEmpty);
      await tester.pumpAndSettle();

      final written = writtenRows();
      expect(written, hasLength(1),
          reason: 'the saved meal must be on disk, not only in the list');
      expect(written.single, contains('My breakfast'));
      expect(find.text('My breakfast'), findsOneWidget);

      // No save-failed banner: the screen reports what actually happened.
      expect(find.textContaining('save the template'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    } finally {
      f.dir.deleteSync(recursive: true);
      pp.deleteSync(recursive: true);
    }
  });

  testWidgets('logging a saved meal on a past day stamps that day',
      (tester) async {
    final f = await _store('day_tmpl_');
    final pp = Directory.systemTemp.createTempSync('nutrition_day_tmpl_pp_');
    PathProviderPlatform.instance = _FakePathProvider(pp);
    await tester.runAsync(() => f.store.createLocal(
          startedAt: yesterdayNoon(),
          itemName: 'Leftovers',
          mealSlot: 'dinner',
          calories: 700,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();

      await tester.tap(find.byTooltip('Save as meal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Dinner again');
      await tester.runAsync(() async {
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Save meal'),
        ));
      });
      await _pumpUntil(
          tester, () => find.text('Dinner again').evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Log'));
      });
      await _pumpUntil(tester, () => f.store.rows.length == 2);
      await tester.pumpAndSettle();

      final stamps = [
        for (final r in f.store.rows)
          DateTime.parse(r['started_at'] as String).toLocal(),
      ];
      expect(stamps.every((s) => sameDay(s, yesterdayNoon())), isTrue,
          reason: 'a back-filled template must land on the viewed day: $stamps');

      await tester.pump(const Duration(seconds: 5));
    } finally {
      f.dir.deleteSync(recursive: true);
      pp.deleteSync(recursive: true);
    }
  });

  testWidgets('logging a saved recipe on a past day stamps that day',
      (tester) async {
    final f = await _store('day_recipe_');
    final pp = Directory.systemTemp.createTempSync('nutrition_day_recipe_pp_');
    PathProviderPlatform.instance = _FakePathProvider(pp);
    await tester.runAsync(() => f.store.createLocal(
          startedAt: yesterdayNoon(),
          itemName: 'Leftovers',
          mealSlot: 'dinner',
          calories: 700,
        ));
    try {
      await tester.pumpWidget(_app(f.store));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();

      await tester.tap(find.byTooltip('Save as recipe'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Big pot');
      await tester.runAsync(() async {
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Save recipe'),
        ));
      });
      await _pumpUntil(
          tester, () => find.text('Big pot').evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Log'));
      });
      await _pumpUntil(tester, () => f.store.rows.length == 2);
      await tester.pumpAndSettle();

      final stamps = [
        for (final r in f.store.rows)
          DateTime.parse(r['started_at'] as String).toLocal(),
      ];
      expect(stamps.every((s) => sameDay(s, yesterdayNoon())), isTrue,
          reason: 'a back-filled recipe must land on the viewed day: $stamps');

      await tester.pump(const Duration(seconds: 5));
    } finally {
      f.dir.deleteSync(recursive: true);
      pp.deleteSync(recursive: true);
    }
  });
}
