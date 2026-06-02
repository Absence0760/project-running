import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/period_summary_screen.dart';

late Directory _runsDir;

Future<({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('period_summary_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  return (runStore: runStore, routeStore: LocalRouteStore(), prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester, {
  required PeriodType period,
  required DateTime anchor,
  required LocalRunStore runStore,
  required LocalRouteStore routeStore,
  required Preferences prefs,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PeriodSummaryScreen(
        initialPeriod: period,
        initialAnchor: anchor,
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('PeriodSummaryScreen — initial render', () {
    testWidgets('app-bar title is "Weekly Summary" when initialPeriod is week',
        (tester) async {
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.text('Weekly Summary'), findsOneWidget);
    });

    testWidgets('app-bar title is "Monthly Summary" when initialPeriod is month',
        (tester) async {
      // Reason: the title swaps based on _period — flipping to the
      // wrong label would imply the period type is wrong.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.month,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.text('Monthly Summary'), findsOneWidget);
    });

    testWidgets('renders prev/next chevrons in the app bar',
        (tester) async {
      // Reason: the chevrons walk the anchor forward and back —
      // their absence would strand users on the initial period.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows "No runs this week" empty state', (tester) async {
      // Reason: with an empty run store the period summary should
      // surface a no-runs hint rather than render a blank scaffold.
      final s = await _makeStores();
      await _pump(
        tester,
        period: PeriodType.week,
        anchor: DateTime(2026, 4, 27),
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump();
      expect(find.text('No runs this week'), findsOneWidget);
    });
  });
}
