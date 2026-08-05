import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader, TextLane;
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
    testWidgets('first frame shows the full-body loader', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold carrying nothing but the loader.
      await _pump(tester);
      expect(find.byType(FullBodyLoader), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
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

  group('WorkoutDetailScreen — unlink confirm', () {
    testWidgets('Cancel does not unlink; confirm calls markCompleted(null)',
        (tester) async {
      final training = _FakeTraining(_completedWorkout(), const []);
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // Tap Unlink → confirm dialog appears.
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      expect(find.text('Unlink run'), findsOneWidget);

      // Cancel → no mutation.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(training.markCalled, isFalse);

      // Tap Unlink again → confirm via the dialog's Unlink button.
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Unlink'),
        ),
      );
      await tester.pumpAndSettle();

      expect(training.markCalled, isTrue);
      expect(training.lastMarkRunId, isNull);
    });
  });

  group('WorkoutDetailScreen — the structure lane holds a localized term', () {
    // Each structure row is `term | value` with the term in a 90px box.
    // Portuguese "Desaquecimento" needs 105.7px in real Roboto at labelMedium
    // w700 and carries no break opportunity, so it painted straight over the
    // value beside it — at 1.0x, before the OS text scale entered it. German
    // "Wiederholungen" and Spanish "Repeticiones" are the same shape. The pair
    // now reflows (a Wrap) rather than sharing one line at any cost, because
    // at 2x a term and its value genuinely do not fit side by side.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane that clears its
    // term's intrinsic width here clears it on a device too.
    PlanWorkoutRow _structured() => PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: 'interval',
          targetDistanceM: 8000,
          manuallyCompleted: false,
          structure: const {
            'warmup': {'distance_m': 1500},
            'cooldown': {'distance_m': 1500},
          },
        );

    Future<void> pumpPortuguese(WidgetTester tester, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: WorkoutDetailScreen(
            training: _FakeTraining(_structured(), const []),
            planId: 'fake-plan-id',
            workoutId: 'fake-workout-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder termLane() => find.ancestor(
          of: find.text('Desaquecimento'),
          matching: find.byType(TextLane),
        );

    testWidgets('the term lane widens to the term instead of overpainting',
        (tester) async {
      await pumpPortuguese(tester);
      expect(termLane(), findsOneWidget);
      final term =
          tester.renderObject<RenderParagraph>(find.text('Desaquecimento'));
      expect(
        tester.getSize(termLane()).width,
        greaterThanOrEqualTo(term.getMaxIntrinsicWidth(double.infinity)),
      );
      expect(term.size.height, lessThan(term.preferredLineHeight * 2),
          reason: 'the term must stay one line tall');
    });

    testWidgets('the term lane floor grows with the OS text scale',
        (tester) async {
      await pumpPortuguese(tester, scale: 2.0);
      expect(tester.takeException(), isNull,
          reason: 'the pair reflows rather than overrunning the card');
      expect(tester.getSize(termLane()).width, greaterThanOrEqualTo(180));
    });
  });
}
