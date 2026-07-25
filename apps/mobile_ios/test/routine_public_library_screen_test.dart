import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/routine_public_library_screen.dart';

GymRoutineRow _routine(String id, String title) => GymRoutineRow(
      id: id,
      authorId: 'author-$id',
      title: title,
      periodisation: 'none',
      exerciseCount: 1,
      lastModifiedAt: DateTime.utc(2026, 5, 1),
      createdAt: DateTime.utc(2026, 5, 1),
      isPublicTemplate: true,
    );

class _LibraryApi extends ApiClient {
  _LibraryApi(this.entries);
  final List<({GymRoutineRow routine, String? authorHandle})> entries;

  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get userId => 'u-viewer';

  @override
  Future<List<({GymRoutineRow routine, String? authorHandle})>>
      fetchPublicGymRoutineLibrary({String query = ''}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => e.routine.title.toLowerCase().contains(q))
        .toList();
  }
}

class _AdoptApi extends ApiClient {
  _AdoptApi(this.clonedId);
  final String clonedId;

  @override
  String? get userId => 'u-viewer';

  @override
  Future<String> cloneGymRoutineTemplate(String templateId) async => clonedId;

  @override
  Future<GymRoutineRow> createGymRoutine({
    String? id,
    required String title,
    String? notes,
    DateTime? lastModifiedAt,
    List<GymRoutineExerciseInput> exercises = const [],
  }) async =>
      throw Exception('offline');

  @override
  Future<({
    GymRoutineRow routine,
    List<({GymRoutineExerciseRow exercise, List<GymRoutineSetRow> sets})>
        exercises,
  })?> fetchGymRoutineDetail(String id) async => (
        routine: _routine(id, 'Adopted'),
        exercises: [
          (
            exercise: GymRoutineExerciseRow(
              id: 'ex-$id',
              routineId: id,
              exerciseName: 'Squat',
              exerciseKey: 'squat',
              position: 0,
              modality: 'weight_reps',
              progression: 'none',
              progressionParams: const <String, dynamic>{},
            ),
            sets: [
              GymRoutineSetRow(
                id: 'set-$id',
                routineExerciseId: 'ex-$id',
                setIndex: 0,
                setType: 'working',
                targetRepsMin: 5,
                targetWeightKg: 100,
              ),
            ],
          ),
        ],
      );
}

({Map<String, dynamic> routine, List<StoredRoutineExercise> exercises})
    _stored(String id) => (
          routine: <String, dynamic>{
            'id': id,
            'title': id,
            'exercise_count': 1,
            'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
          },
          exercises: [
            StoredRoutineExercise(
              exerciseName: 'Row',
              exerciseKey: 'row',
              sets: [StoredRoutineSet(targetRepsMin: 5)],
            ),
          ],
        );

Future<({LocalRoutineStore store, LocalGymStore gym, Directory dir})> _fixture(
    String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_pub_lib_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: Directory('${dir.path}/routines'));
  final gym = LocalGymStore();
  await gym.init(overrideDirectory: Directory('${dir.path}/gym'));
  return (store: store, gym: gym, dir: dir);
}

Widget _app(ApiClient api, LocalRoutineStore store, LocalGymStore gym) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutinePublicLibraryScreen(api: api, store: store, gymStore: gym),
    );

void main() {
  testWidgets('lists public routines with author handle', (tester) async {
    final f = await _fixture('list');
    try {
      final api = _LibraryApi([
        (routine: _routine('r-1', 'Wendler 5/3/1'), authorHandle: 'Coach Sam'),
      ]);
      await tester.pumpWidget(_app(api, f.store, f.gym));
      await tester.pump();
      await tester.pump();
      expect(find.text('Wendler 5/3/1'), findsOneWidget);
      expect(find.text('by Coach Sam'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('empty library renders the empty state', (tester) async {
    final f = await _fixture('empty');
    try {
      await tester.pumpWidget(_app(_LibraryApi(const []), f.store, f.gym));
      await tester.pump();
      await tester.pump();
      expect(find.text('No published routines yet.'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('adopting a public routine keeps the rest of the local library',
      (tester) async {
    final f = await _fixture('adopt');
    try {
      await tester.runAsync(() async {
        await f.store.replaceFromServer(
            [_stored('r-1'), _stored('r-2'), _stored('r-3')]);
        final pending =
            await f.store.createLocal(title: 'Offline', exercises: const []);
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RoutinePublicPreviewScreen(
            api: _AdoptApi('r-adopted'),
            store: f.store,
            gymStore: f.gym,
            entry: (routine: _routine('r-pub', 'Wendler'), authorHandle: null),
          ),
        ));
        await tester.pump();
        await Future<void>.delayed(Duration.zero);
        await tester.pump();
        // The extended FAB animates in; tap only once it is hit-testable.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byType(FloatingActionButton));
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          f.store.routines.map((r) => r.id),
          unorderedEquals(['r-1', 'r-2', 'r-3', pending.id, 'r-adopted']),
        );
        expect(f.store.byId(pending.id)!.syncState,
            RoutineSyncState.pendingCreate);
      });
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
