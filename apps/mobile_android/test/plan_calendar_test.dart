import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training.dart';
import '../lib/widgets/plan_calendar.dart';
import '../lib/workout_kind_color.dart';

/// The kind edge is a `foregroundDecoration` left border on the cell Container;
/// reading it back is how the mark's colour is pinned without a golden.
Color _kindEdgeColor(WidgetTester tester, Finder label) {
  final container = tester.widgetList<Container>(
    find.ancestor(of: label, matching: find.byType(Container)),
  ).firstWhere((c) => c.foregroundDecoration is BoxDecoration &&
      (c.foregroundDecoration as BoxDecoration).border != null);
  return ((container.foregroundDecoration as BoxDecoration).border as Border)
      .left
      .color;
}

void main() {
  testWidgets('renders the start month with workout pills', (tester) async {
    // Use a plan range entirely in the past so the calendar's "open
    // to today's month if in range" heuristic falls back to month 0
    // (the start month) regardless of when this test runs. Without
    // that, a wall-clock date inside the range opens the calendar on
    // the wrong month and the TEMPO pill — which lives in the start
    // month — is off-screen on first paint.
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 6, 30);
    final wo = PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2024, 4, 15),
      kind: 'tempo',
      targetDistanceM: 10000,
      manuallyCompleted: false,
    );

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: [wo],
        ),
      ),
    ));
    await tester.pump();

    // The kind label is uppercased in the cell.
    expect(find.text('TEMPO'), findsOneWidget);
    // Starting month opens to today (or first available month). Either way the
    // header text should match a real month string.
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('navigates between months via chevrons', (tester) async {
    final start = DateTime(2026, 1, 1);
    final end = DateTime(2026, 12, 31);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: const [],
        ),
      ),
    ));
    // The previous-month chevron should be enabled when the visible
    // month isn't the first one. For determinism, push next a few times
    // then back.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    // No assertion on text — the point is the buttons don't crash and
    // the widget rebuilds without throwing.
  });

  testWidgets('shows a tick on completed workouts', (tester) async {
    // Past-dated for the same wall-clock determinism reason as the
    // first test — see that comment.
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 4, 30);
    final wo = PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2024, 4, 10),
      kind: 'long',
      targetDistanceM: 18000,
      completedRunId: 'run-1',
      manuallyCompleted: false,
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: [wo],
        ),
      ),
    ));
    await tester.pump();
    // The completed marker is the small filled tick icon.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows a tick on a manually-completed workout (no linked run)',
      (tester) async {
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 4, 30);
    final wo = PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2024, 4, 10),
      kind: 'tempo',
      targetDistanceM: 8000,
      completedRunId: null,
      manuallyCompleted: true,
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: [wo],
        ),
      ),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('month header survives a narrow width without overflowing',
      (tester) async {
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 4, 30);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: SingleChildScrollView(
              child: PlanCalendar(
                startDate: start,
                endDate: end,
                workouts: const [],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    // The month title sits between two chevron buttons; at 200 it must
    // ellipsize instead of throwing a RenderFlex overflow (the harness
    // fails the test on one).
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  // Issue #666 round 12. The kind hue is a MARK on the cell edge; the kind
  // LABEL reads the `onSurface` text token, because the palette is measured to
  // 1.4.11's 3:1 and the label owes 1.4.3's 4.5:1.
  testWidgets('the kind hue paints the cell edge and never the label',
      (tester) async {
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 4, 30);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: [
            PlanWorkoutRow(
              id: 'wo1',
              weekId: 'wk1',
              scheduledDate: DateTime(2024, 4, 15),
              kind: 'marathon_pace',
              targetDistanceM: 20000,
              manuallyCompleted: false,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    final label = find.text('MARATHON PACE');
    expect(label, findsOneWidget);
    expect(
      _kindEdgeColor(tester, label),
      workoutKindMarkColor(AppTheme.light, WorkoutKind.marathonPace),
    );
    final style = tester.widget<Text>(label).style!;
    expect(style.color, AppTheme.light.colorScheme.onSurface);
    for (final c in ChartPalette.light.kinds) {
      expect(style.color, isNot(c));
    }
  });

  // A 0.55 opacity over the whole cell subtree drops `onSurfaceVariant` to
  // 2.582:1 on the light card, so a planned session that happens to fall in the
  // grid's leading or trailing week is not dimmed — only empty chrome cells are.
  testWidgets('an out-of-month cell carrying a workout is not dimmed',
      (tester) async {
    // April 2024 opens first; 2024-05-01 is a Wednesday, so it renders in the
    // April grid's trailing row while still inside the plan range.
    final start = DateTime(2024, 4, 1);
    final end = DateTime(2024, 5, 31);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlanCalendar(
          startDate: start,
          endDate: end,
          workouts: [
            PlanWorkoutRow(
              id: 'wo1',
              weekId: 'wk1',
              scheduledDate: DateTime(2024, 5, 1),
              kind: 'tempo',
              targetDistanceM: 10000,
              manuallyCompleted: false,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    final label = find.text('TEMPO');
    expect(label, findsOneWidget);
    expect(find.ancestor(of: label, matching: find.byType(Opacity)),
        findsNothing);
    // The dim still applies to the empty cells around it.
    expect(find.byType(Opacity), findsWidgets);
  });
}
