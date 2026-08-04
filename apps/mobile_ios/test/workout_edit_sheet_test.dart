import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/training_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/workout_edit_sheet.dart';

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
      manuallyCompleted: false,
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
      // Full-screen dialog presentation (was a bottom sheet).
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
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

    testWidgets(
        'invalid distance + pace flag their own fields in ONE save attempt; '
        'editing clears each; save then proceeds (issue #666 U6)',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
        tester,
        _workout(targetDistanceM: null, targetPaceSecPerKm: null, notes: ''),
        training,
      );
      final distanceField = find.widgetWithText(TextField, 'e.g. 8.0');
      final paceField = find.widgetWithText(TextField, 'e.g. 5:30');
      await tester.enterText(distanceField, 'abc');
      await tester.enterText(paceField, 'notapace');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(
          tester.widget<TextField>(distanceField).decoration?.errorText,
          'Enter a positive distance in km');
      expect(tester.widget<TextField>(paceField).decoration?.errorText,
          'Pace must look like 5:30');
      expect(training.lastUpdate, isNull);

      await tester.enterText(distanceField, '10');
      await tester.pump();
      expect(tester.widget<TextField>(distanceField).decoration?.errorText,
          isNull);
      expect(tester.widget<TextField>(paceField).decoration?.errorText,
          isNotNull);

      await tester.enterText(paceField, '5:00');
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNotNull);
      expect(training.lastUpdate!.targetDistanceM, closeTo(10000, 1));
      expect(training.lastUpdate!.targetPaceSecPerKm, 300);
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

  group('WorkoutEditSheet — discard guard', () {
    testWidgets('unedited form: Cancel pops with no discard confirm',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(training.lastUpdate, isNull);
    });

    testWidgets(
        'edited form: system back shows the confirm; dialog Cancel keeps the edit',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.enterText(find.widgetWithText(TextField, '8.0'), '12.0');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);

      // The sheet has its own Cancel button — scope to the dialog's.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('12.0'), findsOneWidget);
    });

    testWidgets(
        'edited form: the Cancel button routes through the confirm; Discard pops without saving',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.enterText(find.widgetWithText(TextField, '8.0'), '12.0');
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(AppBar), findsNothing);
      expect(training.lastUpdate, isNull);
    });
  });
}
