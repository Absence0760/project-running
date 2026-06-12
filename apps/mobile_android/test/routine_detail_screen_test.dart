import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/routine_detail_screen.dart';

Future<({LocalRoutineStore store, LocalGymStore gym, Directory dir})> _fixture(
    String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_detail_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: Directory('${dir.path}/routines'));
  final gym = LocalGymStore();
  await gym.init(overrideDirectory: Directory('${dir.path}/gym'));
  return (store: store, gym: gym, dir: dir);
}

Widget _app(LocalRoutineStore store, LocalGymStore gym, String id) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutineDetailScreen(
          api: null, store: store, gymStore: gym, routineId: id),
    );

void main() {
  testWidgets('renders planned targets + the Start FAB', (tester) async {
    final f = await _fixture('targets');
    try {
      await tester.runAsync(() => f.store.replaceFromServer([
            (
              routine: <String, dynamic>{
                'id': 'r-1',
                'title': 'Leg day',
                'exercise_count': 1,
                'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
                'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
              },
              exercises: [
                StoredRoutineExercise(
                  exerciseName: 'Squat',
                  exerciseKey: 'squat',
                  supersetGroup: 1,
                  supersetOrder: 0,
                  progression: 'linear',
                  sets: [
                    StoredRoutineSet(
                        setType: 'warmup', targetRepsMin: 5, targetWeightKg: 100),
                    StoredRoutineSet(
                        targetRepsMin: 8, targetRepsMax: 12, targetWeightKg: 80),
                  ],
                ),
              ],
            ),
          ]));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1'));
      await tester.pump();

      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      // Modality-aware target: reps × weight (single combined cell).
      expect(find.text('5 × 100.0 kg'), findsOneWidget);
      expect(find.text('8–12 × 80.0 kg'), findsOneWidget);
      // Set type + superset badge + progression chip render (P2/P4).
      expect(find.text('Warm-up'), findsOneWidget);
      expect(find.text('Superset 1'), findsOneWidget);
      expect(find.text('Linear'), findsOneWidget);
      // Start FAB present (P1 prefill-only).
      expect(find.text('Start routine'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a missing routine renders the not-found state', (tester) async {
    final f = await _fixture('missing');
    try {
      await tester.pumpWidget(_app(f.store, f.gym, 'nope'));
      await tester.pump();
      expect(find.text('Routine not found.'), findsOneWidget);
      expect(find.text('Start routine'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
