import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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
              (exerciseName: 'Bench', reps: 5, weightKg: 100.0, rpe: null, durationS: null, exerciseId: null),
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
