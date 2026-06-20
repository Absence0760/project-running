import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/widgets/gym_compose_sheet.dart';

Future<({LocalGymStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('gym_compose_$tag');
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

/// A host whose button pushes the composer as a route, so the sheet's
/// `Navigator.pop(context, true)` on save returns cleanly to a parent route
/// (popping a root route in a test is an error).
Widget _opener(LocalGymStore store, {String? existingId}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showGymComposeSheet(
                context: ctx,
                store: store,
                existing: existingId == null ? null : store.byId(existingId),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('empty save shows the validation error and writes nothing',
      (tester) async {
    final f = await _store('validate_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();
      await tester.tap(find.text('Save workout'));
      await tester.pump();
      expect(find.text('Add at least one exercise with a name.'),
          findsOneWidget);
      expect(f.store.workouts, isEmpty);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('entering an exercise + saving creates a workout in the store',
      (tester) async {
    final f = await _store('create_');
    try {
      await tester.pumpWidget(_opener(f.store));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Title field is the first TextField; exercise name is the second.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Leg day');
      await tester.enterText(fields.at(1), 'Squat');
      await tester.enterText(fields.at(2), '5'); // reps
      await tester.enterText(fields.at(3), '140'); // weight

      await tester.tap(find.text('Save workout'));
      // The composer's save awaits a real file write (createLocal) — flush the
      // real event loop so it completes, then settle the route pop.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(f.store.workouts, hasLength(1));
      final w = f.store.workouts.first;
      expect(w.row['title'], 'Leg day');
      expect(w.syncState, GymSyncState.pendingCreate);
      expect(w.sets, hasLength(1));
      expect(w.sets.first['exercise_name'], 'Squat');
      expect(w.sets.first['reps'], 5);
      expect(w.sets.first['weight_kg'], 140.0);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'typing a catalogue name binds exercise_id; free text leaves it null',
      (tester) async {
    // Migration 20270222_001: the composer is ADDITIVE. A typed name matching a
    // catalogue entry (by normalised key) binds that exercise_id onto the set;
    // any other typed name stays free-text with exercise_id null.
    final f = await _store('catalogue_');
    try {
      const catalogue = <GymCatalogueEntry>[
        (name: 'Bench Press', id: 'cat-bench-1', category: 'chest', authorId: null),
      ];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, catalogue: catalogue),
        ),
      ));
      await tester.pump();

      // Row layout: title(0); name(1) reps(2) weight(3) rpe(4) dur(5). Type a
      // catalogue name with different casing / spacing — still binds by key.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Bench day');
      await tester.enterText(fields.at(1), 'bench  press');
      await tester.enterText(fields.at(2), '5');
      // Dismiss the autocomplete overlay before tapping Save.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.text('Save workout'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(f.store.workouts, hasLength(1));
      final sets = f.store.workouts.first.sets;
      expect(sets, hasLength(1));
      expect(sets.first['exercise_name'], 'bench  press');
      expect(sets.first['exercise_id'], 'cat-bench-1');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a free-text name with no catalogue match logs exercise_id null',
      (tester) async {
    final f = await _store('catalogue_free_');
    try {
      const catalogue = <GymCatalogueEntry>[
        (name: 'Bench Press', id: 'cat-bench-1', category: 'chest', authorId: null),
      ];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, catalogue: catalogue),
        ),
      ));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Odd day');
      await tester.enterText(fields.at(1), 'Made-up Lift');
      await tester.enterText(fields.at(2), '8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.text('Save workout'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(f.store.workouts, hasLength(1));
      final sets = f.store.workouts.first.sets;
      expect(sets, hasLength(1));
      expect(sets.first['exercise_name'], 'Made-up Lift');
      expect(sets.first['exercise_id'], isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'catalogue browse/picker: search + pick fills the name and binds exercise_id (decisions §176)',
      (tester) async {
    // The browse/picker UI: open the catalogue, search, tap an entry — the
    // block name fills and the saved set binds the picked exercise_id by
    // normalised key. No api needed for the browse-and-pick path.
    final f = await _store('picker_');
    try {
      const catalogue = <GymCatalogueEntry>[
        (name: 'Deadlift', id: 'cat-dead-1', category: 'legs', authorId: null),
        (name: 'Bench Press', id: 'cat-bench-1', category: 'chest', authorId: null),
      ];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, catalogue: catalogue),
        ),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), 'Pull day');

      // Open the catalogue picker for the first (only) exercise block.
      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Exercise catalogue'), findsOneWidget);

      // The picker's search field is the first TextField on the picker route.
      await tester.enterText(find.byType(TextField).first, 'Deadlift');
      await tester.pumpAndSettle();
      // Tap the result row, scoped to the ListTile (the search field also
      // shows the "Deadlift" text, so a bare text finder is ambiguous).
      await tester.tap(
        find.descendant(of: find.byType(ListTile), matching: find.text('Deadlift')),
      );
      await tester.pumpAndSettle();

      // Back on the composer, the block name field carries the picked name.
      expect(find.text('Deadlift'), findsOneWidget);

      // Reps + save → the set binds the picked exercise_id.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), '3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.text('Save workout'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(f.store.workouts, hasLength(1));
      final sets = f.store.workouts.first.sets;
      expect(sets, hasLength(1));
      expect(sets.first['exercise_name'], 'Deadlift');
      expect(sets.first['exercise_id'], 'cat-dead-1');
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('catalogue browse button hides when no catalogue is supplied',
      (tester) async {
    final f = await _store('picker_hidden_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('prefillTitle seeds a NEW composer title (class -> gym seam)',
      (tester) async {
    final f = await _store('prefill_');
    try {
      // The class -> gym seam opens a NEW composer (existing == null) with the
      // class discipline pre-filled as the title; sets stay empty.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, prefillTitle: 'Vinyasa yoga'),
        ),
      ));
      await tester.pump();
      expect(find.text('Vinyasa yoga'), findsOneWidget);
      // No exercise pre-filled — one blank exercise block awaits the user.
      expect(find.text('Bench'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a timed-only set saves duration_s with no reps/weight',
      (tester) async {
    final f = await _store('duration_');
    try {
      await tester.pumpWidget(_opener(f.store));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Fields per row: title(0), exercise(1), reps(2), weight(3), rpe(4),
      // duration(5). Fill only the exercise + the duration (a 90 s plank).
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Core');
      await tester.enterText(fields.at(1), 'Plank');
      await tester.enterText(fields.at(5), '90'); // duration seconds

      await tester.tap(find.text('Save workout'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(f.store.workouts, hasLength(1));
      final w = f.store.workouts.first;
      expect(w.sets, hasLength(1));
      expect(w.sets.first['exercise_name'], 'Plank');
      expect(w.sets.first['duration_s'], 90);
      expect(w.sets.first['reps'], isNull);
      expect(w.sets.first['weight_kg'], isNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('editing pre-fills the duration from the stored workout',
      (tester) async {
    final f = await _store('edit_dur_');
    const id = 'w-edit-dur';
    await tester.runAsync(() => f.store.replaceFromServer([
          (
            workout: <String, dynamic>{
              'id': id,
              'title': 'Hold day',
              'started_at': DateTime.utc(2026, 3, 1).toIso8601String(),
              'is_public': false,
            },
            sets: <Map<String, dynamic>>[
              {
                'exercise_name': 'Plank',
                'reps': null,
                'weight_kg': null,
                'rpe': null,
                'duration_s': 60,
              },
            ],
          ),
        ]));
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, existing: f.store.byId(id)),
        ),
      ));
      await tester.pump();
      expect(find.text('Plank'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('editing pre-fills the title + set list from the stored workout',
      (tester) async {
    final f = await _store('edit_');
    const id = 'w-edit-1';
    // Seed a genuinely-synced row (replaceFromServer on an empty store).
    // replaceFromServer rewrites the disk cache — a real async file write that
    // only completes on the real event loop, not the testWidgets fake clock.
    await tester.runAsync(() => f.store.replaceFromServer([
          (
            workout: <String, dynamic>{
              'id': id,
              'title': 'Old title',
              'started_at': DateTime.utc(2026, 3, 1).toIso8601String(),
              'is_public': false,
            },
            sets: <Map<String, dynamic>>[
              {
                'exercise_name': 'Bench',
                'reps': 5,
                'weight_kg': 80.0,
                'rpe': null
              },
            ],
          ),
        ]));
    expect(f.store.byId(id)!.syncState, GymSyncState.synced);
    try {
      // Pump the composer directly with `existing` — asserts the unique edit
      // behaviour (initExercises reconstruction + pre-population). The
      // save→pendingUpdate write path is covered by local_gym_store_test
      // (updateLocal) and the create test above proves the composer writes
      // through the store.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GymComposeSheet(store: f.store, existing: f.store.byId(id)),
        ),
      ));
      await tester.pump();

      // Title + the set's exercise name, reps and weight all pre-fill (the
      // integral 80.0 renders without the trailing .0).
      expect(find.text('Old title'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
