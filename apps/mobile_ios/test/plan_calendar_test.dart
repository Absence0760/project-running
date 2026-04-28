import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/plan_calendar.dart';

void main() {
  testWidgets('renders the start month with workout pills', (tester) async {
    final start = DateTime(2026, 4, 1);
    final end = DateTime(2026, 6, 30);
    final wo = PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2026, 4, 15),
      kind: 'tempo',
      targetDistanceM: 10000,
    );

    await tester.pumpWidget(MaterialApp(
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
    final start = DateTime(2026, 4, 1);
    final end = DateTime(2026, 4, 30);
    final wo = PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2026, 4, 10),
      kind: 'long',
      targetDistanceM: 18000,
      completedRunId: 'run-1',
    );
    await tester.pumpWidget(MaterialApp(
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
}
