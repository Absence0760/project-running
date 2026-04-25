import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/training_service.dart';
import 'package:mobile_android/widgets/workout_edit_sheet.dart';

class _FakeTraining extends TrainingService {
  ({
    String workoutId,
    String? kind,
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
  })? lastUpdate;
  Object? errorToThrow;

  @override
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastUpdate = (
      workoutId: workoutId,
      kind: kind,
      targetDistanceM: targetDistanceM,
      targetPaceSecPerKm: targetPaceSecPerKm,
      notes: notes,
    );
  }
}

PlanWorkoutRow _workout({
  String kind = 'tempo',
  double? targetDistanceM = 8000,
  int? targetPaceSecPerKm = 300,
  String? notes = 'Easy effort',
}) =>
    PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2026, 4, 25),
      kind: kind,
      targetDistanceM: targetDistanceM,
      targetPaceSecPerKm: targetPaceSecPerKm,
      notes: notes,
    );

Future<bool?> _pumpSheet(
  WidgetTester tester,
  PlanWorkoutRow workout,
  _FakeTraining training,
) async {
  bool? result;
  await tester.binding.setSurfaceSize(const Size(400, 700));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await showWorkoutEditSheet(
                ctx,
                workout: workout,
                training: training,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('WorkoutEditSheet', () {
    testWidgets('pre-populates kind, distance, and notes from the workout',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      // Distance 8.0 km
      expect(find.text('8.0'), findsOneWidget);
      // Notes field
      expect(find.text('Easy effort'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid pace format', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(targetPaceSecPerKm: null), training);
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. 5:30'),
        'notapace',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pace must look like'), findsOneWidget);
    });

    testWidgets('Cancel returns false and does not call updateWorkout',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNull);
    });

    testWidgets('Save calls updateWorkout with the edited values', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
        tester,
        _workout(targetDistanceM: 10000, targetPaceSecPerKm: null, notes: ''),
        training,
      );
      // Edit the distance.
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. 8.0'),
        '12.0',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNotNull);
      expect(training.lastUpdate!.targetDistanceM, closeTo(12000, 1));
    });
  });
}
