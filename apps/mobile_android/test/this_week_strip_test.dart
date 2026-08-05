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
  double textScale = 1.0,
  double width = 400,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: ThisWeekStrip(
                runs: runs,
                unit: unit,
                weekStartDay: weekStartDay,
                now: now,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Rendered height of the fill bar for the day cell at [index] (0-based
/// within the week row) — the bar IS the chart, so a zero here means the
/// strip rendered blank.
double _barHeight(WidgetTester tester, int index) {
  final bars = find.descendant(
    of: find.byType(FractionallySizedBox),
    matching: find.byType(Container),
  );
  return tester.getSize(bars.at(index)).height;
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

    testWidgets('header row survives a narrow width without overflowing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ThisWeekStrip(
                  runs: const [],
                  unit: DistanceUnit.km,
                  weekStartDay: 'monday',
                  now: wed,
                ),
              ),
            ),
          ),
        ),
      );
      // The title + total share one row; at 320 the title must ellipsize
      // instead of throwing a RenderFlex overflow (the harness fails the
      // test on one).
      expect(find.text('This Week'), findsOneWidget);
    });

    group('OS text scaling', () {
      final runs = [
        _run(startedAt: DateTime(2026, 6, 8, 7), distanceM: 12340),
        _run(startedAt: DateTime(2026, 6, 10, 7), distanceM: 5000),
      ];

      testWidgets('does not overflow at 2x text scale', (tester) async {
        // Pre-fix: seven RenderFlex overflows (one per day cell) plus a
        // header-row overflow — the cell was pinned at 76 px while two
        // labelSmall lines alone need 64 px at 2x.
        await _pump(tester, runs: runs, now: wed, textScale: 2.0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the fill bar survives 2x text scale', (tester) async {
        // The regression that matters: under the fixed 76 px cell the
        // Expanded lane was squeezed to exactly 0 at 2x, so the chart
        // rendered as seven empty boxes.
        await _pump(tester, runs: runs, now: wed, textScale: 1.0);
        final at1x = _barHeight(tester, 0);
        expect(at1x, greaterThan(0));

        await _pump(tester, runs: runs, now: wed, textScale: 2.0);
        expect(_barHeight(tester, 0), at1x);
      });

      testWidgets('the cell grows instead of clipping, and cells stay uniform',
          (tester) async {
        await _pump(tester, runs: runs, now: wed, textScale: 1.0);
        final small = tester.getSize(find.byType(IntrinsicHeight)).height;
        // The cell was a fixed 76 before the fix; letting it size itself must
        // not inflate the 1.0x rhythm. (77, not 76: today's cell carries a
        // 1.5 px border that used to eat into the bar lane instead.)
        expect(small, lessThanOrEqualTo(78));

        await _pump(tester, runs: runs, now: wed, textScale: 2.0);
        expect(tester.getSize(find.byType(IntrinsicHeight)).height,
            greaterThan(small));

        // Every day cell shares the row height — a rest day ("·") must not
        // render shorter than a logged one.
        final cells = find.descendant(
          of: find.byType(IntrinsicHeight),
          matching: find.byType(Opacity),
        );
        final cellHeights = <double>{
          for (var i = 0; i < 7; i++) tester.getSize(cells.at(i)).height,
        };
        expect(cellHeights.length, 1);
      });
    });
  });
}
