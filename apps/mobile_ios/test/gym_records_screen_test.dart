import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/exercise_records.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/gym_exercise_screen.dart';
import '../lib/screens/gym_records_screen.dart';
import '../lib/screens/gym_screen.dart' show gymSetHistory;

StoredGymWorkout _w(
  String id, {
  DateTime? startedAt,
  List<Map<String, dynamic>> sets = const [],
}) =>
    StoredGymWorkout(
      row: {
        'id': id,
        'started_at': (startedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
        'is_public': false,
      },
      sets: sets,
      syncState: GymSyncState.synced,
    );

Map<String, dynamic> _s(String name, {num? reps, num? weight}) => {
      'exercise_name': name,
      'reps': reps,
      'weight_kg': weight,
    };

class _OfflineFakeApi extends ApiClient {
  @override
  String? get userId => null;
}

void main() {
  setUpAll(() => initializeDateFormatting());

  test('gymSetHistory flattens every workout set with its workout id + date', () {
    final history = gymSetHistory([
      _w('a',
          startedAt: DateTime.utc(2026, 2, 1),
          sets: [_s('Bench', reps: 5, weight: 100), _s('Squat', reps: 5, weight: 140)]),
      _w('b',
          startedAt: DateTime.utc(2026, 2, 8),
          sets: [_s('Bench', reps: 3, weight: 105)]),
    ]);
    expect(history.length, 3);
    final bench = history.where((s) => s.exerciseName == 'Bench').toList();
    expect(bench.map((s) => s.workoutId).toSet(), {'a', 'b'});
    expect(bench.firstWhere((s) => s.workoutId == 'a').startedAt,
        DateTime.utc(2026, 2, 1).toIso8601String());
    // Records roll-up sees the flattened history.
    final records = exerciseRecords(history);
    expect(records.map((r) => r.exerciseName), containsAll(['Bench', 'Squat']));
  });

  testWidgets('records screen lists a weighted exercise and opens its progression',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('gym_records_');
    final store = LocalGymStore();
    await store.init(overrideDirectory: dir);
    await tester.runAsync(() async {
      await store.createLocal(
        startedAt: DateTime.utc(2026, 2, 1),
        sets: const [(exerciseName: 'Bench', reps: 5, weightKg: 100.0, rpe: null, durationS: null, exerciseId: null)],
      );
      await store.createLocal(
        startedAt: DateTime.utc(2026, 2, 8),
        sets: const [(exerciseName: 'Bench', reps: 3, weightKg: 110.0, rpe: null, durationS: null, exerciseId: null)],
      );
    });
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GymRecordsScreen(api: _OfflineFakeApi(), store: store),
      ));
      await tester.pump();
      expect(find.text('Personal records'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      // Two distinct sessions logged.
      expect(find.text('2 sessions'), findsOneWidget);

      await tester.tap(find.text('Bench'));
      await tester.pumpAndSettle();
      // Drilled into the progression screen (its own scaffold title = exercise).
      expect(find.byType(GymExerciseScreen), findsOneWidget);
      // Headline session count on the progression screen.
      expect(find.text('2 sessions'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('records screen shows the empty state with no weighted lifts',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('gym_records_empty_');
    final store = LocalGymStore();
    await store.init(overrideDirectory: dir);
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GymRecordsScreen(api: _OfflineFakeApi(), store: store),
      ));
      await tester.pump();
      expect(
        find.textContaining('No weighted lifts logged yet'),
        findsOneWidget,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
