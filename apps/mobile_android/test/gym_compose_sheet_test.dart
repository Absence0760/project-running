import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show TextLane;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/widgets/gym_compose_sheet.dart';

/// Flush the real event loop until [ready] holds, then settle the route pop.
///
/// The composer's save awaits a real atomic file write, so the store's row only
/// appears once the real zone has run. A fixed `Future.delayed` is a guess at
/// how long that takes: it passed on a developer machine and failed on a slower
/// CI runner, and the `finally` that deletes the temp directory then raced the
/// write still in flight. Waiting on the condition itself ends as soon as the
/// write lands and only reports a failure when the save is genuinely broken.
Future<void> _settleUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
}

Future<({LocalGymStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('gym_compose_$tag');
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

/// A store whose create always fails, to drive the composer's save-error path.
class _ThrowingGymStore extends LocalGymStore {
  @override
  Future<StoredGymWorkout> createLocal({
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    Map<String, dynamic>? metadata,
    List<GymSetInput> sets = const [],
  }) async {
    throw Exception('disk full');
  }
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

  testWidgets(
      'the need-exercise error renders on the name field, clears on typing, '
      'and save then proceeds (issue #666 U6)', (tester) async {
    final f = await _store('perfield_');
    try {
      await tester.pumpWidget(_opener(f.store));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.text('Save workout'));
      await tester.pump();

      // Per-field, not form-level: the message is the exercise-name
      // field's errorText (TextField 0 is the title, 1 the name).
      final nameField =
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(nameField.decoration?.errorText,
          'Add at least one exercise with a name.');
      expect(f.store.workouts, isEmpty);

      await tester.enterText(find.byType(TextField).at(1), 'Squat');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .decoration
              ?.errorText,
          isNull);

      await tester.enterText(find.byType(TextField).at(2), '5');
      // The whole save runs inside runAsync: the earlier workouts read
      // primed the store's revision-keyed cache, and only a real-zone tap
      // lets the atomic file write's await chain complete so the
      // revision bump invalidates it.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save workout'));
      });
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);
      expect(f.store.workouts, hasLength(1));
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
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

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

  testWidgets('rapid double-tap Save creates only one workout',
      (tester) async {
    final f = await _store('double_');
    try {
      await tester.pumpWidget(_opener(f.store));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'Squat'); // exercise name
      await tester.enterText(fields.at(2), '5'); // reps

      // First tap starts the async save and (synchronously) flips _saving.
      await tester.tap(find.text('Save workout'));
      // Rebuild → the button now shows the saving spinner + onPressed is null.
      await tester.pump();
      // A second tap while the write is still in flight must be dropped by the
      // _saving guard — not create a second workout / pop twice.
      await tester.tap(find.byType(FilledButton));

      // Now let the real file write complete and settle the route pop.
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

      expect(f.store.workouts, hasLength(1));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a failed save surfaces the error and writes nothing',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('gym_compose_savefail_');
    final store = _ThrowingGymStore();
    await store.init(overrideDirectory: dir);
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: store)),
      ));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'Squat'); // exercise name
      await tester.enterText(fields.at(2), '5'); // reps

      await tester.tap(find.text('Save workout'));
      // The failing store rejects inside the same async chain, so wait on the
      // rendered error rather than on a duration.
      await _settleUntil(
          tester, () => find.text("Couldn't save workout.").evaluate().isNotEmpty);
      await tester.pump();

      expect(find.text("Couldn't save workout."), findsOneWidget);
      // The sheet stays open and re-enables the Save button for a retry.
      expect(find.text('Save workout'), findsOneWidget);
      expect(store.workouts, isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
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
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

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
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

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
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

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
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

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

  testWidgets('set_type defaults to working and a chosen type persists',
      (tester) async {
    // Migration 20270224_001: each logged set carries a set_type. The composer
    // defaults a set to 'working'; picking 'warmup' from the dropdown persists.
    final f = await _store('settype_');
    try {
      await tester.pumpWidget(_opener(f.store));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Leg day');
      await tester.enterText(fields.at(1), 'Squat');
      await tester.enterText(fields.at(2), '5');
      await tester.enterText(fields.at(3), '40');

      // Open the first set's type dropdown and pick Warm-up.
      await tester.tap(find.byKey(const Key('gym-set-type-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warm-up').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save workout'));
      await _settleUntil(tester, () => f.store.workouts.isNotEmpty);

      expect(f.store.workouts, hasLength(1));
      final sets = f.store.workouts.first.sets;
      expect(sets, hasLength(1));
      expect(sets.first['set_type'], 'warmup');
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

  testWidgets(
      'tapping trash on an exercise with data shows a confirm dialog; '
      'Cancel keeps the exercise and its typed sets', (tester) async {
    final f = await _store('remove_cancel_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'Squat'); // exercise name
      await tester.enterText(fields.at(2), '5'); // reps

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Remove exercise?'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'confirming the remove-exercise dialog removes the exercise and its sets',
      (tester) async {
    final f = await _store('remove_confirm_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'Squat'); // exercise name
      await tester.enterText(fields.at(2), '5'); // reps

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Remove')));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Squat'), findsNothing);
      expect(find.text('5'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'tapping trash on an empty exercise block removes it with no confirmation dialog',
      (tester) async {
    final f = await _store('remove_empty_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      // The block auto-refills with a fresh blank exercise, not zero blocks.
      expect(find.byType(TextField), findsWidgets);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'the first set row has no remove button; a second set row does',
      (tester) async {
    final f = await _store('remove_set_gate_');
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GymComposeSheet(store: f.store)),
      ));
      await tester.pump();

      // One exercise block with a single set — the first set can't be removed,
      // so no remove (x) button renders.
      expect(find.byTooltip('Remove set'), findsNothing);

      // Add a second set; only the second (si >= 1) gets a remove button.
      await tester.tap(find.text('Add set'));
      await tester.pump();
      expect(find.byTooltip('Remove set'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  group('GymComposeSheet — the set-number lane holds its localized label', () {
    // "Set N" sat in a 44px box. French/Portuguese "Série 12" needs 50.5px in
    // real Roboto at bodySmall and Spanish "Serie 12" the same, so the label
    // reflowed inside its box at 1.0x, before the OS text scale entered it.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane that clears its
    // label's intrinsic width here clears it on a device too.
    // The default 800dp surface, deliberately: the sheet's set-type dropdown
    // and exercise header carry their own narrow-width overflows under the
    // fixed-advance test font, which this round does not own.
    Future<void> pumpFrench(WidgetTester tester, LocalGymStore store) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        ),
        home: Scaffold(body: GymComposeSheet(store: store)),
      ));
      await tester.pump();
    }

    Finder setLane() => find.ancestor(
          of: find.text('Série 1'),
          matching: find.byType(TextLane),
        );

    testWidgets('the lane widens to the label instead of reflowing it',
        (tester) async {
      final f = await _store('lane_');
      try {
        await pumpFrench(tester, f.store);
        expect(setLane(), findsOneWidget);
        final label = tester.renderObject<RenderParagraph>(find.text('Série 1'));
        expect(
          tester.getSize(setLane()).width,
          greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity)),
        );
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });

    // The text-scale half of the derivation is pinned on the sibling lane in
    // gym_detail_screen_test: the surface carries other narrow-width lanes
    // that overflow at 2x on their own account under the fixed-advance test
    // font, which this round does not own.
  });

  group('GymComposeSheet — the §486 action row', () {
    // Cancel/Save is a RUN OF BUTTONS with nothing at the opposite end, so it
    // takes §486's end-aligned treatment (`OverflowBar`) rather than the
    // opposing-ends `Expanded(Wrap)` the goal editor needs — there is no
    // anchor to preserve.
    //
    // Both cases pin the DERIVATION, never a width: flutter_test's font is
    // fixed-advance and 2-6x wider than Roboto (§500), so "stacked here" holds
    // a fortiori on a device, and the 1.0x case pins that the bar only
    // overflows when it must.
    Future<void> pumpSheet(WidgetTester tester, LocalGymStore store,
        {required double scale, required double width}) async {
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: GymComposeSheet(store: store)),
      ));
      await tester.pump();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pump();
    }

    testWidgets('keeps Cancel and Save on one run at 1.0x', (tester) async {
      final f = await _store('bar1x_');
      try {
        await pumpSheet(tester, f.store, scale: 1.0, width: 800);
        final cancel = tester.getRect(find.text('Cancel'));
        final save = tester.getRect(find.text('Save workout'));
        expect(cancel.top, save.top, reason: 'the bar reflowed with room left');
        expect(save.left, greaterThan(cancel.right),
            reason: 'Save must follow Cancel, end-aligned');
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });

    // 480, not 320: under the fixed-advance test font the sheet's set-type
    // dropdown and exercise header overflow on their own account below ~470,
    // and this round owns only the action row. 480 still puts the pre-fix
    // Cancel/Save row over its lane, so the reflow is genuinely exercised.
    testWidgets('stacks Cancel over Save at 2.0x on a narrow surface',
        (tester) async {
      final f = await _store('bar2x_');
      try {
        await pumpSheet(tester, f.store, scale: 2.0, width: 480);
        final cancel = tester.getRect(find.text('Cancel'));
        final save = tester.getRect(find.text('Save workout'));
        expect(save.top, greaterThanOrEqualTo(cancel.bottom),
            reason: 'the action row striped instead of stacking');
      } finally {
        f.dir.deleteSync(recursive: true);
      }
    });
  });
}
