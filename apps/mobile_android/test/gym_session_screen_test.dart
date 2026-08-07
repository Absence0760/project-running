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

/// Three distinct one-set exercises — the smallest routine that can show a
/// rewind past a *skipped* step disturbing an earlier step's logged set.
StoredRoutine _tripleRoutine() => StoredRoutine(
      row: {'id': 'routine-4', 'title': 'Full body', 'exercise_count': 3},
      exercises: [
        StoredRoutineExercise(
          exerciseName: 'Bench',
          exerciseKey: 'bench',
          sets: [
            StoredRoutineSet(targetRepsMin: 10, targetWeightKg: 100, restS: 0),
          ],
        ),
        StoredRoutineExercise(
          exerciseName: 'Squat',
          exerciseKey: 'squat',
          sets: [
            StoredRoutineSet(targetRepsMin: 8, targetWeightKg: 60, restS: 0),
          ],
        ),
        StoredRoutineExercise(
          exerciseName: 'Row',
          exerciseKey: 'row',
          sets: [
            StoredRoutineSet(targetRepsMin: 12, targetWeightKg: 40, restS: 0),
          ],
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

/// Hosts the session behind a launcher route so the pushed screen carries a
/// real AppBar back button — the surface the PopScope guard intercepts.
Widget _launcher(LocalGymStore store, StoredRoutine routine,
        {StoredGymWorkout? resumeDraft}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GymSessionScreen(
                    api: null,
                    routine: routine,
                    gymStore: store,
                    resumeDraft: resumeDraft,
                  ),
                ),
              ),
              child: const Text('open session'),
            ),
          ),
        ),
      ),
    );

Finder _inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog), matching: find.text(text));

/// Alternate real-clock delays (lets store file I/O complete) with pumps
/// (flushes the fake-zone microtasks that resume the awaiting UI code) until
/// [done]. The leave-with-draft path starts its async chain from the pop
/// guard in the fake zone, so a single fixed delay inside runAsync never
/// drains it — same pattern as gym_screen_test's `_pumpUntil`.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after $timeout waiting for the expected state');
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

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
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });

  testWidgets('Abandon shows the leave dialog; Keep going stays in place',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _routine()));
    await tester.pump();

    // The band's Abandon control opens the three-way leave dialog.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Abandon'));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsOneWidget);
    expect(_inDialog('Discard'), findsOneWidget);
    expect(_inDialog('Leave — keep draft'), findsOneWidget);

    // Keep going dismisses the dialog and leaves the entry view in place.
    await tester.tap(_inDialog('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);
  });

  testWidgets('back with nothing logged pops without a dialog',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_launcher(g.store, _routine()));
    await tester.tap(find.text('open session'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsNothing);
    expect(find.text('open session'), findsOneWidget);
    expect(g.store.workouts, isEmpty);
  });

  testWidgets('back mid-session shows the leave dialog; Keep going stays',
      (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_launcher(g.store, _routine()));
    await tester.tap(find.text('open session'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsOneWidget);

    await tester.tap(_inDialog('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Complete set'), findsOneWidget);
  });

  testWidgets('back → Leave pops and keeps a resumable draft', (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_launcher(g.store, _routine()));
    await tester.tap(find.text('open session'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Leave writes the draft file before popping; poll the pop through.
    await tester.tap(_inDialog('Leave — keep draft'));
    await _pumpUntil(tester, () => tester.any(find.text('open session')));
    final draft = g.store.workouts.single;
    expect(draft.sets.length, 1, reason: 'the logged set must survive');
    final meta = draft.row['metadata'] as Map;
    expect(meta['routine_id'], 'routine-1');
    final snap = meta['gym_session_draft'] as Map;
    final results = snap['results'] as List;
    expect((results.single as Map)['status'], 'completed');
  });

  testWidgets('back → Discard pops and deletes the draft', (tester) async {
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_launcher(g.store, _routine()));
    await tester.tap(find.text('open session'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(_inDialog('Discard'));
    await _pumpUntil(tester, () => tester.any(find.text('open session')));
    expect(g.store.workouts, isEmpty,
        reason: 'Discard must not leave an orphan draft row');
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

  testWidgets('Previous after a skipped step keeps the earlier logged set',
      (tester) async {
    // Regression: the screen kept an append-only `_loggedSets` list but only
    // appended on a Complete, so rewinding past a Skip popped an *earlier*
    // exercise's row — and the metadata step-results, read from the runner,
    // then claimed a set the flat gym_sets rows no longer had.
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _tripleRoutine()));
    await tester.pump();

    // Bench: log the prefilled 10 × 100 target.
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    // Squat: skipped by mistake.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip set'));
    await tester.pump();

    // On Row now; go back to redo the squat.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final w = g.store.workouts.single;
    expect(
      w.sets.map((s) => s['exercise_name']).toList(),
      ['Bench', 'Squat', 'Row'],
      reason: 'rewinding past the skipped squat must not delete the bench row',
    );

    // The two writes have to agree: every step-result carrying an actual needs
    // a matching flat set row, or every gym_sets consumer under-counts while
    // the review panel shows a full session.
    final results = (w.row['metadata'] as Map)['gym_step_results'] as List;
    final logged = results
        .cast<Map>()
        .where((r) => r['actual_reps'] != null)
        .toList();
    expect(logged.map((r) => r['exercise_key']).toList(),
        ['bench', 'squat', 'row']);
    expect(logged.length, w.sets.length);
  });

  testWidgets('Previous re-seeds the entered actuals, not the plan targets',
      (tester) async {
    // Regression: the step-transition handler re-seeded from the step's
    // targets, so a rewind replaced the athlete's 8 × 90 with the prescribed
    // 10 × 100 and a re-Complete persisted the plan as the fact.
    final g = await _gymStore(tester);
    addTearDown(() => g.dir.deleteSync(recursive: true));

    await tester.pumpWidget(_screen(g.store, _tripleRoutine()));
    await tester.pump();

    final reps = find.widgetWithText(TextField, 'Reps');
    final weight = find.widgetWithText(TextField, 'kg');
    await tester.enterText(reps, '8');
    await tester.enterText(weight, '90');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
    await tester.pump();

    expect(tester.widget<TextField>(reps).controller!.text, '8',
        reason: 'the rewound step must show what was lifted, not the target');
    expect(tester.widget<TextField>(weight).controller!.text, '90.0');

    // Re-Complete without editing, then skip out to the finish view.
    await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip set'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip set'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final set = g.store.workouts.single.sets.single;
    expect(set['reps'], 8);
    expect(set['weight_kg'], 90);
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
