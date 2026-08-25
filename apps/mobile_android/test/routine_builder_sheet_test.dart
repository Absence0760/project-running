import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_routine_store.dart';
import '../lib/widgets/routine_builder_sheet.dart';
import 'pump_until.dart';

/// A temp-dir-backed store plus a `persisted` probe.
///
/// `OfflineSyncStore.persist` populates the in-memory routines BEFORE its
/// atomic write, and ends with `notifyListeners()` once the row file and the
/// index are both down — so the notification, not the routine count, is what
/// says the write has cleared the temp dir's teardown.
Future<({LocalRoutineStore store, Directory dir, bool Function() persisted})>
    _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_builder_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: dir);
  var persisted = false;
  store.addListener(() => persisted = true);
  return (store: store, dir: dir, persisted: () => persisted);
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
      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await tester.pump();
      expect(find.text('Give the routine a name.'), findsOneWidget);
      expect(f.store.routines, isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'empty save flags title AND exercise name inline at once; editing '
      'clears each; save then proceeds (issue #666 U6)', (tester) async {
    final f = await _store('perfield');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RoutineBuilderSheet(store: f.store)),
      ));
      await tester.pump();
      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await tester.pump();

      // Both invalid fields flag in ONE save attempt, each as its own
      // errorText (TextField 0 is the title, 1 the exercise name).
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(0))
              .decoration
              ?.errorText,
          'Give the routine a name.');
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .decoration
              ?.errorText,
          'Add at least one exercise with a name.');
      expect(f.store.routines, isEmpty);

      await tester.enterText(find.byType(TextField).at(0), 'Push A');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(0))
              .decoration
              ?.errorText,
          isNull);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .decoration
              ?.errorText,
          isNotNull);

      await tester.enterText(find.byType(TextField).at(1), 'Bench');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .decoration
              ?.errorText,
          isNull);

      // Let the focused name field's autoscroll land before scrolling the
      // Save button back into view — otherwise the deferred focus scroll
      // undoes ensureVisible and the tap misses.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      // The save has to start in the real zone — the atomic file write's
      // await chain never resumes under the fake clock.
      await tester.runAsync(() => tester.tap(find.text('Save routine')));
      await pumpUntil(tester, f.persisted,
          describe: "the routine's row + index files to land on disk");
      expect(f.store.routines, hasLength(1));
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

      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await pumpUntil(tester, f.persisted,
          describe: "the routine's row + index files to land on disk");

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

  testWidgets('superset toggle + set-type + rest persist to the store',
      (tester) async {
    final f = await _store('p2');
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
                  name: 'Bench', sets: [RoutineSeedSet(reps: '5', weightKg: 80)]),
              RoutineSeedExercise(
                  name: 'Row', sets: [RoutineSeedSet(reps: '8', weightKg: 60)]),
            ],
          ),
        ),
      ));
      await tester.pump();

      // First exercise's superset toggle (the last exercise has none).
      final toggle = find.byType(SwitchListTile);
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      // Set the first exercise's first-set rest field (last numeric field in
      // the row — width-60 SizedBox holds the rest field).
      final rest = find.widgetWithText(TextField, 'Rest (s)').first;
      await tester.enterText(rest, '90');
      await tester.pump();

      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await pumpUntil(tester, f.persisted,
          describe: "the routine's row + index files to land on disk");

      expect(f.store.routines, hasLength(1));
      final exes = f.store.routines.first.exercises;
      expect(exes, hasLength(2));
      // Toggling the first → both bracket into one superset group.
      expect(exes[0].supersetGroup, 1);
      expect(exes[0].supersetOrder, 0);
      expect(exes[1].supersetGroup, 1);
      expect(exes[1].supersetOrder, 1);
      // Default set type is working; rest captured.
      expect(exes[0].sets.first.setType, 'working');
      expect(exes[0].sets.first.restS, 90);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('per-set RPE round-trips as a non-null target; empty stays null',
      (tester) async {
    final f = await _store('rpe');
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
                sets: [
                  RoutineSeedSet(reps: '5', weightKg: 80),
                  RoutineSeedSet(reps: '5', weightKg: 80),
                ],
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      // Enter an RPE into the first set's RPE field (hint == the gymRpe label,
      // 'RPE'), leaving the second set's RPE blank.
      final rpeFields = find.widgetWithText(TextField, 'RPE');
      expect(rpeFields, findsNWidgets(2));
      await tester.enterText(rpeFields.first, '8.5');
      await tester.pump();

      await tester.ensureVisible(find.text('Save routine'));
      await tester.pump();
      await tester.tap(find.text('Save routine'));
      await pumpUntil(tester, f.persisted,
          describe: "the routine's row + index files to land on disk");

      expect(f.store.routines, hasLength(1));
      final sets = f.store.routines.first.exercises.first.sets;
      expect(sets, hasLength(2));
      // First set carries the authored RPE; empty second stays null.
      expect(sets[0].targetRpe, 8.5);
      expect(sets[1].targetRpe, isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
