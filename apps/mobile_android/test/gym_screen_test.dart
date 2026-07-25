import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/gym_prs.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/gym_screen.dart';

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

void main() {
  // The list rows render a localised date via formatDateMed → intl DateFormat,
  // which needs the locale symbol data loaded once.
  setUpAll(() => initializeDateFormatting());

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
}
