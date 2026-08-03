import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/recap_screen.dart';

/// A year that is always safely in the past, so "next period" is enabled and
/// the recap window never lands on a future month.
final int pastYear = DateTime.now().year - 1;

Directory? _dir;

Run _run(String id, DateTime startedAt, {double distanceMetres = 5000}) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: distanceMetres,
      source: RunSource.app,
    );

Future<({LocalRunStore runStore, Preferences prefs})> _seed(
    List<Run> runs) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _dir = Directory.systemTemp.createTempSync('recap_screen_test_');
  final seed = LocalRunStore();
  await seed.init(overrideDirectory: _dir!);
  for (final r in runs) {
    await seed.save(r);
  }
  // Fresh store over the same directory so _loadAll has the runs in memory
  // before the screen's first frame.
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _dir!);
  return (runStore: runStore, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester, {
  required LocalRunStore runStore,
  required Preferences prefs,
  int? year,
  int? month,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RecapScreen(
        runStore: runStore,
        preferences: prefs,
        year: year,
        month: month,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  tearDown(() {
    if (_dir != null && _dir!.existsSync()) _dir!.deleteSync(recursive: true);
    _dir = null;
  });

  testWidgets('a month arg opens the monthly recap scoped to that month',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('july', DateTime(pastYear, 7, 4, 8)),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 3);

    expect(find.text('Month in running'), findsOneWidget);
    expect(find.text('March $pastYear'), findsOneWidget);
    // Only the March run counts — the July one belongs to another month.
    expect(find.text('across 1 run'), findsOneWidget);
  });

  testWidgets('the period toggle switches month to the whole year',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([
        _run('march', DateTime(pastYear, 3, 12, 8)),
        _run('july', DateTime(pastYear, 7, 4, 8)),
      ]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 3);
    expect(find.text('across 1 run'), findsOneWidget);

    await tester.tap(find.text('Year'));
    await tester.pump();

    expect(find.text('Year in running'), findsOneWidget);
    expect(find.text('$pastYear'), findsOneWidget);
    expect(find.text('across 2 runs'), findsOneWidget);
  });

  testWidgets('a month with no activity renders the empty state',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed([_run('march', DateTime(pastYear, 3, 12, 8))]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 4);

    expect(
      find.text('No runs in April $pastYear yet. Log one to see your recap.'),
      findsOneWidget,
    );
    expect(find.text('across 1 run'), findsNothing);
  });

  testWidgets('the previous-month chevron steps across the year boundary',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed(const <Run>[]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    await _pump(tester,
        runStore: runStore, prefs: prefs, year: pastYear, month: 1);
    expect(find.text('January $pastYear'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();

    expect(find.text('December ${pastYear - 1}'), findsOneWidget);
  });

  testWidgets('the next chevron is disabled on the current month',
      (tester) async {
    late LocalRunStore runStore;
    late Preferences prefs;
    await tester.runAsync(() async {
      final s = await _seed(const <Run>[]);
      runStore = s.runStore;
      prefs = s.prefs;
    });

    final now = DateTime.now();
    await _pump(tester,
        runStore: runStore, prefs: prefs, year: now.year, month: now.month);

    final next = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(IconButton),
    ));
    expect(next.onPressed, isNull);
  });
}
