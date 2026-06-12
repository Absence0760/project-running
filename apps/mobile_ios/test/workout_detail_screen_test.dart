import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/relink_candidates.dart';
import '../lib/screens/workout_detail_screen.dart';
import '../lib/training_service.dart';

PlanWorkoutRow _completedWorkout({String? completedRunId = 'run-current'}) {
  return PlanWorkoutRow(
    id: 'fake-workout-id',
    weekId: 'week-1',
    scheduledDate: DateTime(2026, 4, 5),
    kind: 'easy',
    targetDistanceM: 5000,
    completedRunId: completedRunId,
    completedAt: DateTime(2026, 4, 5, 8),
    manuallyCompleted: false,
  );
}

class _FakeTraining extends TrainingService {
  final PlanWorkoutRow workout;
  final List<RelinkCandidateRun> candidates;
  String? lastMarkRunId;
  bool markCalled = false;

  _FakeTraining(this.workout, this.candidates);

  @override
  Future<PlanWorkoutRow?> fetchWorkout(String id) async => workout;

  @override
  Future<List<RelinkCandidateRun>> fetchRelinkCandidates(
    PlanWorkoutRow workout,
  ) async =>
      candidates;

  @override
  Future<void> markCompleted(String workoutId, String? runId,
      {bool manual = false}) async {
    markCalled = true;
    lastMarkRunId = runId;
  }
}

RelinkCandidateRun _cand(String id, String started) => RelinkCandidateRun(
      id: id,
      startedAt: DateTime.parse(started),
      distanceM: 5000,
      durationS: 1800,
    );

Future<void> _pumpWith(WidgetTester tester, _FakeTraining training) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkoutDetailScreen(
        training: training,
        planId: 'fake-plan-id',
        workoutId: 'fake-workout-id',
      ),
    ),
  );
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkoutDetailScreen(
        training: TrainingService(),
        planId: 'fake-plan-id',
        workoutId: 'fake-workout-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('WorkoutDetailScreen — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold with just a centered spinner.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('initial Scaffold has no AppBar yet', (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('WorkoutDetailScreen — re-link picker', () {
    testWidgets('Re-link opens the picker, picking a run calls markCompleted',
        (tester) async {
      final training = _FakeTraining(
        _completedWorkout(),
        [
          _cand('run-current', '2026-04-05T07:00:00Z'),
          _cand('run-other', '2026-04-06T07:00:00Z'),
        ],
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // Completed card shows the Re-link button.
      expect(find.text('Re-link'), findsOneWidget);
      await tester.tap(find.text('Re-link'));
      await tester.pumpAndSettle();

      // Dialog lists both candidate runs.
      expect(find.text('Link a different run'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
      // The current pick is tagged.
      expect(find.text('Current'), findsOneWidget);

      // Pick the non-current run.
      await tester.tap(find.byType(ListTile).at(1));
      await tester.pumpAndSettle();

      expect(training.markCalled, isTrue);
      expect(training.lastMarkRunId, 'run-other');
    });

    testWidgets('picker shows the empty state when no candidates', (tester) async {
      final training = _FakeTraining(_completedWorkout(), const []);
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Re-link'));
      await tester.pumpAndSettle();

      expect(find.text('No eligible runs near this date.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('no Re-link button when the workout is only manually completed',
        (tester) async {
      final training = _FakeTraining(
        _completedWorkout(completedRunId: null),
        const [],
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // A manually-completed workout (no completed_run_id) shows no
      // completed card with run actions — re-link is run-link-only.
      expect(find.text('Re-link'), findsNothing);
    });
  });
}
