import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/training_service.dart';
import 'package:mobile_android/widgets/todays_workout_card.dart';

ActivePlanOverview _overview({
  String kind = 'tempo',
  double? targetDistanceM = 8000,
  int? targetPaceSecPerKm = 330,
  String? completedRunId,
}) {
  final workout = PlanWorkoutRow(
    id: 'wo1',
    weekId: 'wk1',
    scheduledDate: DateTime(2026, 4, 25),
    kind: kind,
    targetDistanceM: targetDistanceM,
    targetPaceSecPerKm: targetPaceSecPerKm,
    completedRunId: completedRunId,
  );
  final plan = TrainingPlanRow(
    id: 'p1',
    userId: 'u1',
    name: 'Marathon plan',
    goalEvent: 'marathon',
    goalDistanceM: 42195,
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 5, 31),
    daysPerWeek: 4,
    status: 'active',
    source: 'generated',
  );
  return ActivePlanOverview(
    plan: plan,
    weeks: const [],
    workouts: [workout],
    todayWorkout: workout,
    completionPct: 10,
    currentWeekIndex: 1,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ActivePlanOverview overview, {
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TodaysWorkoutCard(overview: overview, onTap: onTap),
      ),
    ),
  );
}

void main() {
  group('TodaysWorkoutCard', () {
    testWidgets('renders "TODAY\'S WORKOUT" label for an incomplete workout',
        (tester) async {
      await _pump(tester, _overview());
      expect(find.text("TODAY'S WORKOUT"), findsOneWidget);
    });

    testWidgets('renders "DONE TODAY" label for a completed workout',
        (tester) async {
      await _pump(tester, _overview(completedRunId: 'run-1'));
      expect(find.text('DONE TODAY'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('renders the workout kind label', (tester) async {
      await _pump(tester, _overview(kind: 'tempo'));
      expect(find.text('Tempo'), findsOneWidget);
    });

    testWidgets('renders target distance when provided', (tester) async {
      await _pump(tester, _overview(targetDistanceM: 8000));
      expect(find.textContaining('8'), findsAtLeastNWidgets(1));
    });

    testWidgets('calls onTap when the card is tapped', (tester) async {
      var taps = 0;
      await _pump(tester, _overview(), onTap: () => taps++);
      await tester.tap(find.byType(TodaysWorkoutCard));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
