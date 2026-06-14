import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/this_week_strip.dart';

Run _run({required DateTime startedAt, required double distanceM}) => Run(
      id: 'r-${startedAt.microsecondsSinceEpoch}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.app,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Run> runs,
  DistanceUnit unit = DistanceUnit.km,
  String weekStartDay = 'monday',
  required DateTime now,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThisWeekStrip(
            runs: runs,
            unit: unit,
            weekStartDay: weekStartDay,
            now: now,
          ),
        ),
      ),
    ),
  );
}

void main() {
  final wed = DateTime(2026, 6, 10, 12); // Wednesday

  group('ThisWeekStrip', () {
    testWidgets('renders the title + a zeroed week frame with no runs',
        (tester) async {
      await _pump(tester, runs: const [], now: wed);
      expect(find.text('This Week'), findsOneWidget);
      // Seven day cells render even when empty (matches web — no self-hide).
      expect(find.text('·'), findsNWidgets(7));
    });

    testWidgets('header sums the week distance + activity count', (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 6, 8, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 6, 10, 7), distanceM: 5000),
        ],
        now: wed,
      );
      // 10 km total · 2 activities.
      expect(find.text('10.00 km · 2 activities'), findsOneWidget);
    });

    testWidgets('a single activity uses the singular count form', (tester) async {
      await _pump(
        tester,
        runs: [_run(startedAt: DateTime(2026, 6, 9, 7), distanceM: 3000)],
        now: wed,
      );
      expect(find.text('3.00 km · 1 activity'), findsOneWidget);
    });

    testWidgets('a logged day shows its distance; rest days show a dot',
        (tester) async {
      await _pump(
        tester,
        runs: [_run(startedAt: DateTime(2026, 6, 9, 7), distanceM: 4000)],
        now: wed,
      );
      // One day cell carries the distance; the other six are rest dots.
      expect(find.text('4.00 km'), findsWidgets);
      expect(find.text('·'), findsNWidgets(6));
    });

    testWidgets('honours the mile unit in the header total', (tester) async {
      await _pump(
        tester,
        runs: [_run(startedAt: DateTime(2026, 6, 8, 7), distanceM: 10000)],
        unit: DistanceUnit.mi,
        now: wed,
      );
      // 10 km ≈ 6.21 mi.
      expect(find.text('6.21 mi · 1 activity'), findsOneWidget);
    });

    testWidgets('excludes activities outside the current calendar week',
        (tester) async {
      await _pump(
        tester,
        runs: [
          _run(startedAt: DateTime(2026, 6, 1, 7), distanceM: 9000), // last week
          _run(startedAt: DateTime(2026, 6, 9, 7), distanceM: 2000), // this week
        ],
        now: wed,
      );
      expect(find.text('2.00 km · 1 activity'), findsOneWidget);
    });
  });
}
