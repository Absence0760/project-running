import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/gym_session_screen.dart';

/// No-op so the session screen's `WakelockPlus.enable()` / `.disable()` don't
/// hit the real pigeon channel (which throws under flutter_test).
class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {
    _on = enable;
  }

  @override
  Future<bool> get enabled async => _on;
}

/// A two-set bench routine (working sets, no rest) — the smallest routine that
/// exercises step advance + a final write. `restS: 0` keeps the rest timer out
/// of the test so there's no pending periodic timer to drain.
StoredRoutine _routine({String title = 'Bench routine'}) => StoredRoutine(
      row: {'id': 'routine-1', 'title': title, 'exercise_count': 1},
      exercises: [
        StoredRoutineExercise(
          exerciseName: 'Bench',
          exerciseKey: 'bench',
          sets: [
            StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 80, restS: 0),
            StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 80, restS: 0),
          ],
        ),
      ],
      syncState: RoutineSyncState.synced,
    );

/// A single timed hold (plank) — the modality that used to log its target as
/// though it were the measured actual.
StoredRoutine _timedRoutine() => StoredRoutine(
      row: {'id': 'routine-2', 'title': 'Core', 'exercise_count': 1},
      exercises: [
        StoredRoutineExercise(
          exerciseName: 'Plank',
          exerciseKey: 'plank',
          sets: [StoredRoutineSet(targetDurationS: 60, targetRpe: 8, restS: 0)],
        ),
      ],
      syncState: RoutineSyncState.synced,
    );

/// A single distance carry — the modality whose target never reached the
/// runner, so the set had no input and graded as an unconditional `hit`.
StoredRoutine _distanceRoutine() => StoredRoutine(
      row: {'id': 'routine-3', 'title': 'Carries', 'exercise_count': 1},
      exercises: [
        StoredRoutineExercise(
          exerciseName: 'Farmer carry',
          exerciseKey: 'farmer_carry',
          sets: [StoredRoutineSet(targetDistanceM: 500, restS: 0)],
        ),
      ],
      syncState: RoutineSyncState.synced,
    );

Future<({LocalGymStore store, Directory dir})> _gymStore(
    WidgetTester tester) async {
  late LocalGymStore store;
  late Directory dir;
  await tester.runAsync(() async {
    dir = Directory.systemTemp.createTempSync('gym_session_');
    final s = LocalGymStore();
    await s.init(overrideDirectory: dir);
    store = s;
  });
  return (store: store, dir: dir);
}

Widget _screen(LocalGymStore store, StoredRoutine routine) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api: null → offline; the runner writes the local store only.
      home: GymSessionScreen(api: null, routine: routine, gymStore: store),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();
  });

  testWidgets('renders the entry fields + execution band on the first step',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    // AppBar shows the routine title.
    expect(find.text('Bench routine'), findsOneWidget);
    // The three per-set entry fields.
    expect(find.widgetWithText(TextField, 'Reps'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'kg'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'RPE'), findsOneWidget);
    // The band's Complete-set control on the active step.
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);
  });

  testWidgets('a timed set logs what was entered, not the target',
      (tester) async {
    // Regression: _entered() returned `durationS: step.targetDurationS`, so
    // every timed set persisted an actual duration exactly equal to plan —
    // fabricated data that also made the duration axis of adherence
    // unconditionally green. There was no way to enter a real one.
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _timedRoutine()));
    await tester.pump();

    final field = find.widgetWithText(TextField, 'Time (s)');
    expect(field, findsOneWidget,
        reason: 'a timed step needs a way to record the real duration');
    // Nothing typed yet → nothing to log, not a silent full-credit hit.
    expect(tester.widget<TextField>(field).controller!.text, '');

    await tester.enterText(field, '45');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    // Finish writes the file; let the (api == null) save path settle.
    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final sets = g.store.workouts.single.sets;
    expect(sets.length, 1);
    expect(sets.single['duration_s'], 45,
        reason: 'the logged duration must be the 45 s entered, not the 60 s '
            'target');
  });

  testWidgets('a whole-number target RPE prefills as "8", not "8.0"',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _timedRoutine()));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'RPE'))
          .controller!
          .text,
      '8',
      reason: 'the routine composer already formats RPE this way; the same '
          'routine must not read 8.0 here and 8 there',
    );
  });

  testWidgets('an untimed set shows no duration field', (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Time (s)'), findsNothing);
  });

  testWidgets('a distance set logs what was entered, not the target',
      (tester) async {
    // Regression: GymRunnerStep carried no targetDistanceM, so the target never
    // reached the runner, there was no way to record an actual distance, and
    // computeRoutineAdherence fell through its axis chain to grade the set a
    // flat `hit` no matter what the athlete did.
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _distanceRoutine()));
    await tester.pump();

    // The band surfaces the target the step now carries.
    expect(find.text('500 m'), findsOneWidget);

    final field = find.widgetWithText(TextField, 'Distance (m)');
    expect(field, findsOneWidget,
        reason: 'a distance step needs a way to record the real distance');
    // Nothing typed yet → nothing to log, not a silent full-credit hit.
    expect(tester.widget<TextField>(field).controller!.text, '');

    await tester.enterText(field, '380');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // Distance has no gym_sets column, so the flat set list stays empty — the
    // real distance travels in the metadata step-results instead.
    final workout = g.store.workouts.single;
    expect(workout.sets, isEmpty);
    final results =
        (workout.row['metadata'] as Map)['gym_step_results'] as List;
    expect(results.single['actual_distance_m'], 380,
        reason: 'the logged distance must be the 380 m entered, not the 500 m '
            'target');
    expect(results.single['target_distance_m'], 500);
    expect(results.single['status'], 'partial',
        reason: '380 m is under 80% of the 500 m target');
  });

  testWidgets('an unrecorded distance logs null and is graded unrecorded',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _distanceRoutine()));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final results = ((g.store.workouts.single.row['metadata']
        as Map)['gym_step_results'] as List);
    expect(results.single['actual_distance_m'], isNull);
    expect(results.single['status'], 'partial',
        reason: 'an unlogged distance target is partial, never a hit');
  });

  testWidgets('a set with no distance target shows no distance field',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Distance (m)'), findsNothing);
  });

  testWidgets('Complete on the last step finishes the session', (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    // Complete set 1 → advances to set 2 (still on the entry view).
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);

    // Complete set 2 → workout complete; the finish view + its CTA appear.
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    expect(find.text('Finish'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('Abandon shows a confirm dialog; Cancel keeps the session',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    // The band's Abandon control opens the discard confirm dialog.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Abandon'));
    await tester.pumpAndSettle();
    expect(find.text('Discard session?'), findsOneWidget);

    // Cancel dismisses the dialog and leaves the entry view in place.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard session?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);
  });

  testWidgets(
      'finishing persists a workout carrying the entered sets to the store',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    // Each Complete logs the prefilled target (5 reps × 80 kg) onto the step.
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    // Finish → createLocal writes a file; run it on the real event loop and let
    // the (api == null) save path settle before asserting on the store.
    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // One workout landed, titled from the routine, with both completed sets
    // and the routine-id metadata stamped (the cross-modal review trio).
    expect(g.store.workouts.length, 1);
    final w = g.store.workouts.single;
    expect(w.row['title'], 'Bench routine');
    expect(w.sets.length, 2);
    expect(w.row['metadata']?['routine_id'], 'routine-1');
  });

  testWidgets('an empty-titled routine falls back to a generic AppBar title',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine(title: '   ')));
    await tester.pump();

    // Blank title → the localised "Routines" fallback, never an empty AppBar.
    expect(find.text('Routines'), findsOneWidget);
  });
}
