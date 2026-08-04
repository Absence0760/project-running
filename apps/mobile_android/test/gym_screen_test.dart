import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show ExerciseRow, GymWorkoutRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/gym_prs.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/gym_screen.dart';

/// No-op so a resumed session screen's `WakelockPlus.enable()` / `.disable()`
/// don't hit the real pigeon channel (which throws under flutter_test).
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

/// Build a synced [StoredGymWorkout] inline (no disk) for the pure-helper
/// tests. `sets` are `gym_sets`-shaped maps as the store stores them.
StoredGymWorkout _w(
  String id, {
  String? title,
  DateTime? startedAt,
  List<Map<String, dynamic>> sets = const [],
}) =>
    StoredGymWorkout(
      row: {
        'id': id,
        'title': title,
        'started_at': (startedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
        'is_public': false,
      },
      sets: sets,
      syncState: GymSyncState.synced,
    );

Map<String, dynamic> _s(String name, {num? reps, num? weight, num? rpe}) => {
      'exercise_name': name,
      'reps': reps,
      'weight_kg': weight,
      'rpe': rpe,
    };

/// The pre-tracker derivation `gymPrWorkoutIds` used to run: re-derive the
/// whole prior-PR map for every workout. Kept here as the reference the
/// single-pass [RunningPrTracker] version must reproduce exactly.
Set<String> _referencePrWorkoutIds(List<StoredGymWorkout> workouts) {
  final ids = <String>{};
  final ordered = [...workouts]
    ..sort((a, b) => a.startedAt!.compareTo(b.startedAt!));
  final prior = <GymSetLike>[];
  for (final w in ordered) {
    final mine = [
      for (final s in w.sets)
        GymSetLike(
          exerciseName: (s['exercise_name'] as String?) ?? '',
          reps: s['reps'] as num?,
          weightKg: s['weight_kg'] as num?,
        ),
    ];
    if (workoutPrs(prior, mine).isNotEmpty) ids.add(w.id);
    prior.addAll(mine);
  }
  return ids;
}

class _OfflineFakeApi extends ApiClient {
  @override
  String? get userId => null;
}

/// Online api whose fetches succeed but whose workout push is rejected —
/// the RLS-denial / 500 / expired-token class of failure issue #666 U2 is
/// about: the row stays pending while the screen believes it's online.
class _RejectingSyncApi extends ApiClient {
  @override
  String? get userId => 'user-1';

  @override
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) async => const [];

  @override
  Future<List<ExerciseRow>> fetchExerciseCatalogue() async => const [];

  @override
  Future<GymWorkoutRow> createGymWorkout({
    String? id,
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
    Map<String, dynamic>? metadata,
    List<GymSetInput> sets = const [],
  }) async {
    throw Exception('server rejected');
  }
}

/// Real file I/O driven from mount has no completion hook to await, so poll
/// the observable end-state rather than sleeping a fixed duration (same
/// pattern as nutrition_screen_test).
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

/// A store pair seeded with an in-flight guided-session draft (one logged
/// bench set of a two-set routine) plus the routine it came from — the state
/// a mid-session process kill leaves behind.
Future<({LocalGymStore store, LocalRoutineStore routines, Directory dir})>
    _seedDraft(WidgetTester tester, {bool withRoutine = true}) async {
  late LocalGymStore store;
  late LocalRoutineStore routines;
  late Directory dir;
  await tester.runAsync(() async {
    dir = Directory.systemTemp.createTempSync('gym_screen_draft_');
    store = LocalGymStore();
    await store.init(overrideDirectory: Directory('${dir.path}/gym'));
    routines = LocalRoutineStore();
    await routines.init(overrideDirectory: Directory('${dir.path}/routines'));
    await store.createLocal(
      title: 'Bench routine',
      startedAt: DateTime.utc(2026, 3, 1, 10),
      durationS: 300,
      sets: const [
        (
          exerciseName: 'Bench',
          reps: 5,
          weightKg: 80.0,
          rpe: null,
          setType: 'working',
          durationS: null,
          exerciseId: null,
        ),
      ],
      metadata: {
        'routine_id': 'routine-1',
        'gym_session_draft': {
          'saved_at': '2026-03-01T10:05:00Z',
          'results': [
            {
              'step_index': 0,
              'status': 'completed',
              'reps': 5,
              'weight_kg': 80.0,
              'rpe': null,
              'duration_s': null,
              'distance_m': null,
            },
          ],
        },
      },
    );
    if (withRoutine) {
      await routines.upsertFromServer(
        {
          'id': 'routine-1',
          'title': 'Bench routine',
          'exercise_count': 1,
          'last_modified_at': '2026-03-01T09:00:00.000Z',
        },
        [
          StoredRoutineExercise(
            exerciseName: 'Bench',
            exerciseKey: 'bench',
            sets: [
              StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 80, restS: 0),
              StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 80, restS: 0),
            ],
          ),
        ],
      );
    }
  });
  return (store: store, routines: routines, dir: dir);
}

Widget _gymScreen(LocalGymStore store, LocalRoutineStore routines) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GymScreen(
        api: _OfflineFakeApi(),
        store: store,
        routineStore: routines,
      ),
    );

void main() {
  // The list rows render a localised date via formatDateMed → intl DateFormat,
  // which needs the locale symbol data loaded once.
  setUpAll(() {
    initializeDateFormatting();
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();
  });

  group('gym list pure helpers', () {
    test('gymWorkoutVolume sums reps*weight, ignores incomplete sets', () {
      final w = _w('a', sets: [
        _s('Bench', reps: 5, weight: 100), // 500
        _s('Bench', reps: 3, weight: 100), // 300
        _s('Bench', reps: 5), // no weight → 0
        _s('Squat', weight: 140), // no reps → 0
      ]);
      expect(gymWorkoutVolume(w), 800);
    });

    test('gymExerciseCount counts distinct names case-insensitively', () {
      final w = _w('a', sets: [
        _s('Bench', reps: 5, weight: 100),
        _s('bench', reps: 5, weight: 100),
        _s('Squat', reps: 5, weight: 140),
        _s('  ', reps: 1), // blank ignored
      ]);
      expect(gymExerciseCount(w), 2);
    });

    test('gymPrWorkoutIds: first workout + any later workout that beats it', () {
      final a = _w('a',
          startedAt: DateTime.utc(2026, 1, 1),
          sets: [_s('Bench', reps: 1, weight: 100)]);
      final b = _w('b',
          startedAt: DateTime.utc(2026, 1, 8),
          sets: [_s('Bench', reps: 1, weight: 110)]);
      final c = _w('c',
          startedAt: DateTime.utc(2026, 1, 15),
          sets: [_s('Bench', reps: 1, weight: 90)]); // beats nothing
      // Pass newest-first (as the store yields) — helper sorts internally.
      final ids = gymPrWorkoutIds([c, b, a]);
      expect(ids, containsAll(['a', 'b']));
      expect(ids.contains('c'), isFalse);
    });

    test('gymPrWorkoutIds ignores empty workouts', () {
      final ids = gymPrWorkoutIds([_w('empty')]);
      expect(ids, isEmpty);
    });

    test(
        'gymPrWorkoutIds matches the pre-tracker per-workout derivation over a '
        'non-trivial history', () {
      final history = [
        // First workout — everything in it is a PR.
        _w('w1', startedAt: DateTime.utc(2026, 1, 1), sets: [
          _s('Bench', reps: 5, weight: 100),
          _s('Squat', reps: 5, weight: 140),
        ]),
        // Ties on every metric, beats nothing.
        _w('w2', startedAt: DateTime.utc(2026, 1, 2), sets: [
          _s('Bench', reps: 5, weight: 100),
          _s('Squat', reps: 3, weight: 140),
        ]),
        // Lower-cased spelling normalises onto 'bench'; volume PR only.
        _w('w3', startedAt: DateTime.utc(2026, 1, 3), sets: [
          _s('bench', reps: 8, weight: 90),
        ]),
        // Incomplete sets: no weight, blank name, no reps.
        _w('w4', startedAt: DateTime.utc(2026, 1, 4), sets: [
          _s('Deadlift', reps: 5),
          _s('  ', reps: 5, weight: 200),
          _s('Deadlift', weight: 180),
        ]),
        // Same weight as w4 but now with reps → volume + e1rm PRs.
        _w('w5', startedAt: DateTime.utc(2026, 1, 5), sets: [
          _s('Deadlift', reps: 5, weight: 180),
        ]),
        _w('w6', startedAt: DateTime.utc(2026, 1, 6)),
        _w('w7', startedAt: DateTime.utc(2026, 1, 7), sets: [
          _s('Squat', reps: 1, weight: 150),
        ]),
        // Heaviest is beaten, volume + e1rm exactly tie w1's — no PR.
        _w('w8', startedAt: DateTime.utc(2026, 1, 8), sets: [
          _s('Squat', reps: 5, weight: 140),
        ]),
      ];
      final ids = gymPrWorkoutIds(history);
      expect(ids, _referencePrWorkoutIds(history));
      expect(ids, {'w1', 'w3', 'w4', 'w5', 'w7'});
    });

    test('gymPrWorkoutIds sorts a dateless workout last, deterministically',
        () {
      final dated = _w('a',
          startedAt: DateTime.utc(2026, 1, 1),
          sets: [_s('Bench', reps: 1, weight: 100)]);
      final dateless = StoredGymWorkout(
        row: {
          'id': 'z',
          'title': null,
          'started_at': 'not-a-date',
          'is_public': false,
        },
        sets: [_s('Bench', reps: 1, weight: 90)],
        syncState: GymSyncState.synced,
      );
      // Judged after 'a', so its 90 kg beats nothing. Were it sorted first it
      // would take the bench PR for itself.
      expect(gymPrWorkoutIds([dated, dateless]), {'a'});
      expect(gymPrWorkoutIds([dateless, dated]), {'a'});
    });

    test('gymExerciseSuggestions: most-used first, original spelling kept', () {
      final a = _w('a', sets: [
        _s('Bench Press', reps: 5, weight: 100),
        _s('bench press', reps: 5, weight: 100),
        _s('Squat', reps: 5, weight: 140),
      ]);
      final b = _w('b', sets: [_s('Deadlift', reps: 5, weight: 180)]);
      final out = gymExerciseSuggestions([a, b]);
      // Bench Press used twice → first; original spelling of first occurrence.
      expect(out.first, 'Bench Press');
      expect(out, containsAll(['Bench Press', 'Squat', 'Deadlift']));
    });
  });

  group('GymScreen widget — offline / no api', () {
    testWidgets('renders empty state when the store is empty', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gym_screen_empty_');
      final store = LocalGymStore();
      await store.init(overrideDirectory: dir);
      try {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GymScreen(api: _OfflineFakeApi(), store: store),
        ));
        await tester.pump();
        expect(find.text('No gym workouts yet'), findsOneWidget);
        expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    testWidgets('renders a seeded workout row with its stats', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gym_screen_list_');
      final store = LocalGymStore();
      await store.init(overrideDirectory: dir);
      // createLocal awaits a real file write, which never completes inside the
      // testWidgets fake-async zone — run it on the real event loop.
      await tester.runAsync(() => store.createLocal(
            title: 'Push day',
            startedAt: DateTime.utc(2026, 2, 1),
            sets: const [
              (exerciseName: 'Bench', reps: 5, weightKg: 100.0, rpe: null, setType: null, durationS: null, exerciseId: null),
            ],
          ));
      try {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GymScreen(api: _OfflineFakeApi(), store: store),
        ));
        await tester.pump();
        expect(find.text('Push day'), findsOneWidget);
        expect(find.text('1 exercise'), findsOneWidget);
        // First-ever workout sets a PR → badge shows.
        expect(find.text('PR'), findsOneWidget);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('GymScreen pending-sync banner (issue #666 U2)', () {
    testWidgets(
        'a pending row surfaces the failed-sync banner with Retry when the '
        'server rejects the push while online', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gym_screen_pend_on_');
      final store = LocalGymStore();
      await tester.runAsync(() async {
        await store.init(overrideDirectory: dir);
        await store.createLocal(
            title: 'Push day', startedAt: DateTime.utc(2026, 2, 1));
      });
      try {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GymScreen(api: _RejectingSyncApi(), store: store),
        ));
        await _pumpUntil(
            tester, () => tester.any(find.text("1 change hasn't synced")));
        expect(find.text('Retry'), findsOneWidget);
        expect(store.hasPending, isTrue);
        // Let the in-flight refresh drain before tearing the temp dir down.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    testWidgets('a pending row surfaces the saved-on-device banner offline',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('gym_screen_pend_off_');
      final store = LocalGymStore();
      await tester.runAsync(() async {
        await store.init(overrideDirectory: dir);
        await store.createLocal(
            title: 'Push day', startedAt: DateTime.utc(2026, 2, 1));
      });
      try {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GymScreen(api: _OfflineFakeApi(), store: store),
        ));
        await tester.pump();
        expect(
          find.text('1 change saved on this device — will sync when online'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsNothing);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('GymScreen guided-session resume card (issue #666 U5)', () {
    testWidgets('a draft with a live routine surfaces the resume card',
        (tester) async {
      final s = await _seedDraft(tester);
      addTearDown(() => s.dir.deleteSync(recursive: true));

      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pump();

      expect(find.text('Workout in progress'), findsOneWidget);
      expect(find.text('Bench routine · 1 set logged'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Save as is'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
    });

    testWidgets('no card without a draft marker', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gym_screen_nodraft_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = LocalGymStore();
      final routines = LocalRoutineStore();
      await tester.runAsync(() async {
        await store.init(overrideDirectory: Directory('${dir.path}/gym'));
        await routines.init(
            overrideDirectory: Directory('${dir.path}/routines'));
        await store.createLocal(
            title: 'Push day', startedAt: DateTime.utc(2026, 2, 1));
      });

      await tester.pumpWidget(_gymScreen(store, routines));
      await tester.pump();

      expect(find.text('Workout in progress'), findsNothing);
    });

    testWidgets('no card when the draft routine no longer exists',
        (tester) async {
      final s = await _seedDraft(tester, withRoutine: false);
      addTearDown(() => s.dir.deleteSync(recursive: true));

      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pump();

      // The draft row still lists as a plain workout; only the card hides.
      expect(find.text('Workout in progress'), findsNothing);
      expect(find.text('Bench routine'), findsOneWidget);
    });

    testWidgets(
        'Resume restores the runner mid-routine and finishing completes '
        'the same draft row', (tester) async {
      final s = await _seedDraft(tester);
      addTearDown(() => s.dir.deleteSync(recursive: true));

      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();

      // The replayed draft lands on set 2 of 2, not back at set 1.
      expect(find.text('Bench · set 2 of 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Complete set'));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Finish'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final w = s.store.workouts.single;
      expect(w.sets.length, 2,
          reason: 'the replayed draft set and the freshly logged one must '
              'both persist onto the one draft row');
      final meta = w.row['metadata'] as Map;
      expect(meta.containsKey('gym_session_draft'), isFalse,
          reason: 'finishing must clear the draft marker');
      expect(meta['gym_adherence'], 'completed');
    });

    testWidgets('Save as is keeps the sets and clears the draft marker',
        (tester) async {
      final s = await _seedDraft(tester);
      addTearDown(() => s.dir.deleteSync(recursive: true));

      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Save as is'));
      await _pumpUntil(
          tester, () => !tester.any(find.text('Workout in progress')));

      final w = s.store.workouts.single;
      expect(w.sets.length, 1);
      final meta = w.row['metadata'] as Map;
      expect(meta.containsKey('gym_session_draft'), isFalse);
      expect(meta['routine_id'], 'routine-1');

      // Drain the confirmation banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Discard confirms, then deletes the draft row',
        (tester) async {
      final s = await _seedDraft(tester);
      addTearDown(() => s.dir.deleteSync(recursive: true));

      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Discard session?'), findsOneWidget);

      // Cancel keeps the draft.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Workout in progress'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Discard')));
      await _pumpUntil(
          tester, () => !tester.any(find.text('Workout in progress')));

      expect(s.store.workouts, isEmpty);
    });
  });
}
