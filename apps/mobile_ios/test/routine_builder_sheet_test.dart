import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_routine_store.dart';
import '../lib/widgets/routine_builder_sheet.dart';

Future<({LocalRoutineStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_builder_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

void main() {
  testWidgets('empty title shows the validation error and writes nothing',
      (tester) async {
    final f = await _store('need_title');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RoutineBuilderSheet(store: f.store)),
      ));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await tester.pump();
      expect(find.text('Give the routine a name.'), findsOneWidget);
      expect(f.store.routines, isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('seeded title + exercise saves a routine to the store',
      (tester) async {
    final f = await _store('save');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RoutineBuilderSheet(
            store: f.store,
            seedTitle: 'Push day A',
            seedExercises: [
              RoutineSeedExercise(
                name: 'Bench',
                sets: [RoutineSeedSet(reps: '5', weightKg: 80)],
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      // Seed prefilled the title + exercise name.
      expect(find.text('Push day A'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);

      await tester.tap(find.text('Save routine'));
      // createLocal awaits a real file write — flush the real event loop.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(f.store.routines, hasLength(1));
      final r = f.store.routines.first;
      expect(r.title, 'Push day A');
      expect(r.syncState, RoutineSyncState.pendingCreate);
      expect(r.exercises, hasLength(1));
      expect(r.exercises.first.exerciseName, 'Bench');
      expect(r.exercises.first.exerciseKey, 'bench');
      expect(r.exercises.first.sets.first.targetRepsMin, 5);
      // Weight stored canonical kg (default unit is kg in tests).
      expect(r.exercises.first.sets.first.targetWeightKg, 80.0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
