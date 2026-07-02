import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/current_week_strip.dart';

PlanWorkoutRow _wo(String id, DateTime date, String kind, double? dist,
        {bool done = false, DateTime? skippedAt}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'wk1',
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      completedRunId: done ? 'run-1' : null,
      manuallyCompleted: false,
      skippedAt: skippedAt,
    );

Future<void> _pump(
  WidgetTester tester, {
  required DateTime start,
  required int weekIndex,
  required List<PlanWorkoutRow> workouts,
  void Function(PlanWorkoutRow)? onSelect,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CurrentWeekStrip(
        startDate: start,
        weekIndex: weekIndex,
        weekWorkouts: workouts,
        onSelect: onSelect,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // Past-dated start so the "today" highlight doesn't depend on the
  // wall-clock; the strip's window is anchored to startDate + weekIndex*7.
  final start = DateTime(2024, 4, 1); // a Monday

  testWidgets('renders the heading + a row of seven day cells', (tester) async {
    await _pump(
      tester,
      start: start,
      weekIndex: 0,
      workouts: [_wo('a', DateTime(2024, 4, 2), 'tempo', 10000)],
    );
    expect(find.text('This week'), findsOneWidget);
    // Seven Expanded cells (one per day of the anchored week).
    expect(find.byType(Expanded), findsNWidgets(7));
    expect(find.text('TEMPO'), findsOneWidget);
  });

  testWidgets('completion count reflects done vs active workouts in the week',
      (tester) async {
    await _pump(
      tester,
      start: start,
      weekIndex: 0,
      workouts: [
        _wo('a', DateTime(2024, 4, 2), 'long', 18000, done: true),
        _wo('b', DateTime(2024, 4, 4), 'easy', 8000),
        _wo('c', DateTime(2024, 4, 6), 'rest', null),
      ],
    );
    // 1 completed of 2 active (rest excluded), mirroring the week card.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('a skipped workout is off the books — excluded from the active denominator',
      (tester) async {
    await _pump(
      tester,
      start: start,
      weekIndex: 0,
      workouts: [
        _wo('a', DateTime(2024, 4, 2), 'long', 18000, done: true),
        _wo('b', DateTime(2024, 4, 4), 'easy', 8000),
        // Deliberately skipped — must NOT count toward the active total.
        _wo('c', DateTime(2024, 4, 6), 'tempo', 10000,
            skippedAt: DateTime(2024, 4, 6)),
      ],
    );
    // 1 completed of 2 active (rest AND the skipped tempo both excluded).
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('tapping a workout cell fires onSelect', (tester) async {
    PlanWorkoutRow? tapped;
    final target = _wo('a', DateTime(2024, 4, 3), 'interval', 6000);
    await _pump(
      tester,
      start: start,
      weekIndex: 0,
      workouts: [target],
      onSelect: (w) => tapped = w,
    );
    await tester.tap(find.text('INTERVALS'));
    await tester.pump();
    expect(tapped?.id, 'a');
  });

  testWidgets('window is anchored to weekIndex, not the calendar week',
      (tester) async {
    // weekIndex 2 → the week starting 2024-04-15. A workout dated in that
    // week shows; one dated in week 0 does not (proves the anchor).
    await _pump(
      tester,
      start: start,
      weekIndex: 2,
      workouts: [
        _wo('wk2', DateTime(2024, 4, 16), 'tempo', 10000),
        _wo('wk0', DateTime(2024, 4, 2), 'long', 18000),
      ],
    );
    expect(find.text('TEMPO'), findsOneWidget);
    expect(find.text('LONG RUN'), findsNothing);
  });
}
