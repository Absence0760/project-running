import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_ramp.dart';
import '../lib/widgets/comeback_card.dart';
import '../lib/widgets/load_ramp_card.dart';

final DateTime _now = DateTime.utc(2026, 8, 14, 12);

RunForVolume _run(int daysAgo, double distanceM, [String activityType = 'run']) {
  return RunForVolume(
    startedAt: _now.subtract(Duration(days: daysAgo)).toIso8601String(),
    distanceM: distanceM,
    activityType: activityType,
  );
}

Future<void> _pump(WidgetTester tester, List<RunForVolume> runs,
    {bool comeback = false}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: comeback
              ? ComebackCard(runs: runs, now: _now)
              : LoadRampCard(runs: runs, now: _now),
        ),
      ),
    ),
  );
}

void main() {
  group('LoadRampCard', () {
    testWidgets('a graded month renders the band, the ratio, and both figures',
        (tester) async {
      await _pump(tester, [
        _run(1, 80000),
        _run(8, 40000),
        _run(15, 40000),
        _run(22, 40000),
      ]);
      expect(find.byKey(const Key('dashboardLoadRampCard')), findsOneWidget);
      // (80 + 3*40)/4 = 50 km chronic; 80/50 = 1.60 — the high band.
      expect(find.text('1.60×'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('80.00 km'), findsOneWidget);
      expect(find.text('50.00 km'), findsOneWidget);
      expect(find.text('Your load is ramping up.'), findsOneWidget);
    });

    testWidgets('a thin history renders nothing rather than a zeroed ratio',
        (tester) async {
      // One big run in an otherwise empty month: the ratio would be arithmetic
      // on noise, and a zeroed one reads as a reassuring "safe".
      await _pump(tester, [_run(1, 30000)]);
      expect(find.byKey(const Key('dashboardLoadRampCard')), findsNothing);
    });

    testWidgets('a rest week on a real base is still graded', (tester) async {
      await _pump(tester, [_run(8, 40000), _run(15, 40000), _run(22, 40000)]);
      expect(find.byKey(const Key('dashboardLoadRampCard')), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Your load is tapering off.'), findsOneWidget);
    });
  });

  group('ComebackCard', () {
    List<RunForVolume> comebackRunner(int layoffDays, double thisWeekM) {
      final lastBefore = 1 + layoffDays;
      return [
        _run(1, thisWeekM),
        _run(lastBefore, 40000),
        _run(lastBefore + 7, 40000),
        _run(lastBefore + 14, 40000),
        _run(lastBefore + 21, 40000),
      ];
    }

    testWidgets('a big first week back renders the verdict and the layoff',
        (tester) async {
      await _pump(tester, comebackRunner(70, 36000), comeback: true);
      expect(find.byKey(const Key('dashboardComebackCard')), findsOneWidget);
      expect(find.text('Big first week'), findsOneWidget);
      expect(find.text('10 weeks without a run'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('36.00 km'), findsOneWidget);
      expect(find.text('40.00 km'), findsOneWidget);
    });

    testWidgets('a runner who never stopped renders nothing', (tester) async {
      await _pump(
        tester,
        [_run(1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)],
        comeback: true,
      );
      expect(find.byKey(const Key('dashboardComebackCard')), findsNothing);
    });
  });

  group('the two load cards never both claim the same week', () {
    testWidgets('a comeback history hides the ratio card', (tester) async {
      final runs = [
        _run(1, 36000),
        _run(71, 40000),
        _run(78, 40000),
        _run(85, 40000),
        _run(92, 40000),
      ];
      await _pump(tester, runs);
      expect(find.byKey(const Key('dashboardLoadRampCard')), findsNothing);
      await _pump(tester, runs, comeback: true);
      expect(find.byKey(const Key('dashboardComebackCard')), findsOneWidget);
    });

    testWidgets('a consistent history hides the comeback card', (tester) async {
      final runs = [
        _run(1, 40000),
        _run(8, 40000),
        _run(15, 40000),
        _run(22, 40000),
      ];
      await _pump(tester, runs, comeback: true);
      expect(find.byKey(const Key('dashboardComebackCard')), findsNothing);
      await _pump(tester, runs);
      expect(find.byKey(const Key('dashboardLoadRampCard')), findsOneWidget);
    });
  });
}
