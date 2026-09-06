import 'dart:async';
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
import '../lib/screens/gym_records_screen.dart';
import '../lib/screens/gym_screen.dart';
import '../lib/screens/routine_library_screen.dart';
import '../lib/screens/sessions_screen.dart';
import '../lib/widgets/pending_sync_banner.dart';
import '../lib/widgets/surface_peer_strip.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

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

/// Signed in but unreachable: the mount's refresh throws, so no store write
/// fires in the fake-async zone, while `userId` is non-null so the
/// server-backed peers (session plans) are offered.
class _SignedInOfflineApi extends ApiClient {
  @override
  String? get userId => 'user-1';

  @override
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) async =>
          throw Exception('offline');
}

/// Signed in and believed online, but the mount's fetch never resolves — the
/// state that keeps the failed-sync banner (message + Retry) on screen while a
/// pending row is still queued.
class _HangingApi extends ApiClient {
  @override
  String? get userId => 'user-1';

  @override
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) => Completer<
          List<
              ({
                Map<String, dynamic> workout,
                List<Map<String, dynamic>> sets
              })>>().future;
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
///
/// [describe] is required for the reason § 723 gives: a deadline that expires
/// has to name the condition that never held, and one generic string shared
/// across every call site in a file has given that away.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String describe,
  Duration timeout = const Duration(seconds: 10),
}) =>
    pumpUntil(tester, done, describe: describe, timeout: timeout);

/// Sentinel for "leave the draft marker at its well-formed shape" — null is a
/// value a caller wants to seed, so it cannot double as the default.
const Object _defaultMarker = Object();

const Map<String, Object?> _draftSnapshot = {
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
};

/// A store pair seeded with an in-flight guided-session draft (one logged
/// bench set of a two-set routine) plus the routine it came from — the state
/// a mid-session process kill leaves behind.
Future<({LocalGymStore store, LocalRoutineStore routines, Directory dir})>
    _seedDraft(WidgetTester tester,
        {bool withRoutine = true, Object? draftMarker = _defaultMarker}) async {
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
        'gym_session_draft':
            identical(draftMarker, _defaultMarker) ? _draftSnapshot : draftMarker,
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

    test('gymExerciseCount buckets on the canonical key, not trim+toLowerCase',
        () {
      // The row stat has to answer what every keyed surface answers. An
      // internal whitespace run and a non-breaking space both survive
      // `trim().toLowerCase()`, so this workout used to read as four
      // exercises where `gym_workout_summaries` reports one (§ 1248).
      final w = _w('a', sets: [
        _s('Bench Press', reps: 5, weight: 100),
        _s('Bench  Press', reps: 5, weight: 100),
        _s('bench\u00a0press', reps: 5, weight: 100),
        _s(' BENCH PRESS ', reps: 5, weight: 100),
      ]);
      expect(gymExerciseCount(w), 1);
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

    test('gymExerciseSuggestions merges spellings the canonical fold merges',
        () {
      // The composer's autocomplete is a local re-derivation of what the
      // server's `gym_exercise_names` answers, so it has to bucket the way
      // `exercise_key` does. Keyed on `trim().toLowerCase()` the double space
      // survived, so one lift appeared twice in the list and its use count —
      // which decides the order — was split between the two entries (§ 1248).
      final a = _w('a', sets: [
        _s('Bench  Press', reps: 5, weight: 100),
        _s('Bench Press', reps: 5, weight: 100),
        _s('Squat', reps: 5, weight: 140),
        _s('Squat', reps: 5, weight: 140),
      ]);
      final out = gymExerciseSuggestions([a]);
      expect(out, ['Bench  Press', 'Squat']);
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

  group('GymScreen peer strip (issue #666 T1)', () {
    Future<
        ({
          LocalGymStore store,
          LocalRoutineStore routines,
          Directory dir
        })> seed(WidgetTester tester, {bool withRecord = false}) async {
      late LocalGymStore store;
      late LocalRoutineStore routines;
      late Directory dir;
      await tester.runAsync(() async {
        dir = Directory.systemTemp.createTempSync('gym_screen_peers_');
        store = LocalGymStore();
        await store.init(overrideDirectory: Directory('${dir.path}/gym'));
        routines = LocalRoutineStore();
        await routines.init(overrideDirectory: Directory('${dir.path}/routines'));
        if (withRecord) {
          await store.createLocal(
            title: 'Push day',
            startedAt: DateTime.utc(2026, 2, 1),
            sets: const [
              (
                exerciseName: 'Bench',
                reps: 5,
                weightKg: 100.0,
                rpe: null,
                setType: null,
                durationS: null,
                exerciseId: null
              ),
            ],
          );
        }
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      return (store: store, routines: routines, dir: dir);
    }

    testWidgets('names Log + Routines; Records only once a record exists',
        (tester) async {
      final s = await seed(tester);
      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pumpAndSettle();

      final strip = find.byType(SurfacePeerStrip);
      expect(strip, findsOneWidget);
      expect(
          find.descendant(of: strip, matching: find.text('Log')), findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('Routines')),
          findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('Records')),
          findsNothing);
      // Signed out, so the server-backed session plans are not offered.
      expect(find.descendant(of: strip, matching: find.text('Sessions')),
          findsNothing);
    });

    testWidgets('Records appears once a weighted set is logged, and opens',
        (tester) async {
      final s = await seed(tester, withRecord: true);
      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pumpAndSettle();

      final records = find.descendant(
          of: find.byType(SurfacePeerStrip), matching: find.text('Records'));
      expect(records, findsOneWidget);
      await tester.tap(records);
      await tester.pumpAndSettle();
      expect(find.byType(GymRecordsScreen), findsOneWidget);
    });

    testWidgets('an un-init()ed routine store hides the Routines peer',
        (tester) async {
      // A routine store whose init() threw is resident but directoryless, and
      // every write to it then refuses (decisions § 660). Offering the peer
      // over one advertises a surface that cannot save a routine.
      final s = await seed(tester);
      await tester.pumpWidget(_gymScreen(s.store, LocalRoutineStore()));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(SurfacePeerStrip), matching: find.text('Routines')),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(SurfacePeerStrip), matching: find.text('Log')),
          findsOneWidget);
    });

    testWidgets('Routines opens the routine library', (tester) async {
      final s = await seed(tester);
      await tester.pumpWidget(_gymScreen(s.store, s.routines));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(SurfacePeerStrip), matching: find.text('Routines')));
      await tester.pumpAndSettle();
      expect(find.byType(RoutineLibraryScreen), findsOneWidget);
    });

    testWidgets('a signed-in gym reaches its own session plans',
        (tester) async {
      final s = await seed(tester);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GymScreen(
          api: _SignedInOfflineApi(),
          store: s.store,
          routineStore: s.routines,
        ),
      ));
      await tester.pumpAndSettle();

      final sessions = find.descendant(
          of: find.byType(SurfacePeerStrip), matching: find.text('Sessions'));
      expect(sessions, findsOneWidget);
      await tester.tap(sessions);
      await tester.pumpAndSettle();
      expect(find.byType(SessionsScreen), findsOneWidget);
    });

    testWidgets('the strip and the sync banner survive 320dp in German',
        (tester) async {
      // The narrowest phone the app targets, in the longest locale, with the
      // whole chrome stack up at once: peer strip + the online failed-sync
      // banner over the workout list. The banner's Retry used to take its
      // intrinsic width first and starve the message to a few pixels, growing
      // the banner past the viewport as soon as the strip claimed its 64dp.
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await seed(tester, withRecord: true);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GymScreen(
          api: _HangingApi(),
          store: s.store,
          routineStore: s.routines,
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SurfacePeerStrip), findsOneWidget);
      expect(find.byType(PendingSyncBanner), findsOneWidget);
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
            tester, () => tester.any(find.text("1 change hasn't synced")),
            describe: 'the rejected sync to surface the unsynced-count banner');
        expect(find.text('Retry'), findsOneWidget);
        expect(store.hasPending, isTrue);
        // Let the in-flight refresh drain before tearing the temp dir down.
        await pumpUntilStoreWritesSettle(tester);
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

    // decisions.md § 662: the marker is a draft only when it is a JSON
    // object. A bare presence check offered a resume the runner's own routine
    // history — and the RPC behind it — both count as a session performed.
    testWidgets('a non-object under the draft key surfaces no resume card',
        (tester) async {
      for (final marker in <Object?>[<dynamic>[], 'draft', 7, null]) {
        final s = await _seedDraft(tester, draftMarker: marker);
        addTearDown(() => s.dir.deleteSync(recursive: true));

        await tester.pumpWidget(_gymScreen(s.store, s.routines));
        await tester.pump();

        expect(find.text('Workout in progress'), findsNothing,
            reason: 'marker $marker is not a JSON object, so not a draft');
        expect(find.text('Bench routine'), findsOneWidget,
            reason: 'the row still lists as a plain performed workout');
      }
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

      await tester.tap(find.text('Finish'));
      // The save banner is the last thing _finishAndSave does, so waiting for
      // it proves the store write it awaited first has landed.
      await _pumpUntil(tester, () => tester.any(find.text('Workout saved')),
          describe: 'the saved banner _finishAndSave shows after its write');

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
          tester, () => !tester.any(find.text('Workout in progress')),
          describe: 'the in-progress card to clear after "Save as is"');

      final w = s.store.workouts.single;
      expect(w.sets.length, 1);
      final meta = w.row['metadata'] as Map;
      expect(meta.containsKey('gym_session_draft'), isFalse);
      expect(meta['routine_id'], 'routine-1');

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
          tester, () => !tester.any(find.text('Workout in progress')),
          describe: 'the in-progress card to clear after the discard');

      expect(s.store.workouts, isEmpty);
    });
  });
}
