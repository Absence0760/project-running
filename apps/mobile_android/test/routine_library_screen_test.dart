import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/routine_library_screen.dart';

Future<({LocalRoutineStore store, LocalGymStore gym, Directory dir})> _fixture(
    String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_lib_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: Directory('${dir.path}/routines'));
  final gym = LocalGymStore();
  await gym.init(overrideDirectory: Directory('${dir.path}/gym'));
  return (store: store, gym: gym, dir: dir);
}

Widget _app(LocalRoutineStore store, LocalGymStore gym) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutineLibraryScreen(api: null, store: store, gymStore: gym),
    );

void main() {
  testWidgets('empty library renders the self-hiding onboarding state',
      (tester) async {
    final f = await _fixture('empty');
    try {
      await tester.pumpWidget(_app(f.store, f.gym));
      await tester.pump();
      expect(find.text('No routines yet'), findsOneWidget);
      // No routine rows.
      expect(find.byType(Card), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a seeded routine renders a row with title + exercise count',
      (tester) async {
    final f = await _fixture('seeded');
    try {
      await tester.runAsync(() => f.store.replaceFromServer([
            (
              routine: <String, dynamic>{
                'id': 'r-1',
                'title': 'Push day A',
                'exercise_count': 2,
                'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
                'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
              },
              exercises: [
                StoredRoutineExercise(
                    exerciseName: 'Bench', exerciseKey: 'bench', sets: const []),
                StoredRoutineExercise(
                    exerciseName: 'Press', exerciseKey: 'press', sets: const []),
              ],
            ),
          ]));
      await tester.pumpWidget(_app(f.store, f.gym));
      await tester.pump();
      expect(find.text('Push day A'), findsOneWidget);
      expect(find.text('2 exercises'), findsOneWidget);
      expect(find.text('No routines yet'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
