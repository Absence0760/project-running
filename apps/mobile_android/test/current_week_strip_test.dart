import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training.dart';
import '../lib/widgets/current_week_strip.dart';
import '../lib/workout_kind_color.dart';

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
  ThemeData? theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
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
    // Seven Expanded cells, one per day of the anchored week. The header
    // contributes none — ChartCardHeader reflows in a Wrap rather than
    // bounding its title with an Expanded.
    expect(find.byType(Expanded), findsNWidgets(7));
    expect(find.text('TEMPO'), findsOneWidget);
  });

  testWidgets('header row survives a narrow width without overflowing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            child: CurrentWeekStrip(
              startDate: start,
              weekIndex: 0,
              weekWorkouts: [_wo('a', DateTime(2024, 4, 2), 'tempo', 10000)],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    // Title + done/active counter share one run; at 220 the counter must
    // drop to its own line instead of throwing a RenderFlex overflow (the
    // harness fails the test on one) — and neither text is truncated.
    expect(find.text('This week'), findsOneWidget);
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

  // Issue #666 round 12: the same contract as `plan_calendar` — the strip is
  // the second copy of the palette the two surfaces used to drift between.
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('the kind hue paints the cell edge and never the label in $name',
        (tester) async {
      await _pump(
        tester,
        start: start,
        weekIndex: 0,
        theme: theme,
        workouts: [_wo('a', DateTime(2024, 4, 2), 'interval', 6000)],
      );
      final label = find.text('INTERVALS');
      expect(label, findsOneWidget);

      final container = tester
          .widgetList<Container>(
              find.ancestor(of: label, matching: find.byType(Container)))
          .firstWhere((c) =>
              c.foregroundDecoration is BoxDecoration &&
              (c.foregroundDecoration as BoxDecoration).border != null);
      final edge =
          ((container.foregroundDecoration as BoxDecoration).border as Border)
              .left;
      expect(edge.color, workoutKindMarkColor(theme, WorkoutKind.interval));

      final style = tester.widget<Text>(label).style!;
      expect(style.color, theme.colorScheme.onSurface);
      for (final c in ChartPalette.ofTheme(theme).kinds) {
        expect(style.color, isNot(c));
      }
    });
  }

  // ───────────────────────── DST window drift ─────────────────────────
  //
  // The strip's window used `startDate.add(Duration(days: n))`, which steps
  // absolute time. A local calendar day is 25 hours on a fall-back, so a
  // 6*24h step from the Monday of that week lands at 23:00 on the Sunday
  // BEFORE the seventh day: the sixth date is emitted twice and the seventh —
  // the long run, on a Sunday-ending plan week — never renders at all.
  //
  // These cases only reproduce the drift when the suite runs in a zone that
  // has the transition (`TZ=America/New_York` exercises 2024-11-03); in UTC
  // they hold trivially. `calendar_day_arithmetic_guard_test.dart` is the
  // timezone-independent half that catches the shape wherever CI runs.

  /// One workout per day of the window, each tagged with a distinct distance
  /// so a missing or duplicated day is visible in the rendered cells.
  List<PlanWorkoutRow> _week(DateTime firstDay) => [
        for (var i = 0; i < 7; i++)
          _wo('d$i', DateTime(firstDay.year, firstDay.month, firstDay.day + i),
              'easy', (i + 1) * 1000),
      ];

  Future<void> _expectSevenDistinctDays(WidgetTester tester) async {
    for (var i = 0; i < 7; i++) {
      expect(find.text('${i + 1}.0 km'), findsOneWidget,
          reason: 'day ${i + 1} of the plan week should render exactly once');
    }
  }

  testWidgets('renders all seven days when the window crosses a fall-back',
      (tester) async {
    // 2024-10-29 (Tue) → 2024-11-04 (Mon); 2024-11-03 is 25 hours long.
    final dstStart = DateTime(2024, 10, 29);
    await _pump(
      tester,
      start: dstStart,
      weekIndex: 0,
      workouts: _week(dstStart),
    );
    await _expectSevenDistinctDays(tester);
  });

  testWidgets('anchors the window correctly when the plan start is weeks back',
      (tester) async {
    // Five weeks of 24-hour blocks from 2024-10-01 fall an hour short of the
    // calendar date, dropping the anchor onto the previous day and shifting
    // every cell in the row.
    final planStart = DateTime(2024, 10, 1);
    final weekOneDay = DateTime(2024, 11, 5);
    await _pump(
      tester,
      start: planStart,
      weekIndex: 5,
      workouts: _week(weekOneDay),
    );
    await _expectSevenDistinctDays(tester);
  });
}
