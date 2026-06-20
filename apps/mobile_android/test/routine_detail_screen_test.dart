import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_routine_store.dart';
import '../lib/screens/routine_detail_screen.dart';
import '../lib/social_service.dart';

Future<({LocalRoutineStore store, LocalGymStore gym, Directory dir})> _fixture(
    String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_detail_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: Directory('${dir.path}/routines'));
  final gym = LocalGymStore();
  await gym.init(overrideDirectory: Directory('${dir.path}/gym'));
  return (store: store, gym: gym, dir: dir);
}

Widget _app(LocalRoutineStore store, LocalGymStore gym, String id,
        {SocialService? social, String? viewerId}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutineDetailScreen(
          api: null,
          store: store,
          gymStore: gym,
          routineId: id,
          social: social,
          viewerIdOverride: viewerId),
    );

class _FakeSocial extends SocialService {
  final List<ClubView> clubs;
  _FakeSocial(this.clubs);
  @override
  Future<List<ClubView>> fetchMyClubs() async => clubs;
}

ClubView _club(String id, String name, String role) => ClubView(
      row: ClubRow(shadowHidden: false, 
        id: id,
        ownerId: 'owner',
        name: name,
        slug: name.toLowerCase(),
        isPublic: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        joinPolicy: 'open',
        memberCount: 3,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 3,
      viewerRole: role,
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

Map<String, dynamic> _row(String id, String title,
        {String? authorId, String? clubId}) =>
    <String, dynamic>{
      'id': id,
      'author_id': authorId,
      'club_id': clubId,
      'title': title,
      'exercise_count': 1,
      'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
      'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
    };

List<({Map<String, dynamic> routine, List<StoredRoutineExercise> exercises})>
    _seed(Map<String, dynamic> row) => [
          (
            routine: row,
            exercises: [
              StoredRoutineExercise(
                exerciseName: 'Squat',
                exerciseKey: 'squat',
                sets: [StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 100)],
              ),
            ],
          ),
        ];

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

  testWidgets(
      'publish control shows for an author of a personal routine with an admin club',
      (tester) async {
    final f = await _fixture('publish_show');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1',
          social: _FakeSocial([_club('c-1', 'Track Club', 'admin')]),
          viewerId: 'me'));
      // initState fetches admin clubs asynchronously.
      await tester.pump();
      await tester.pump();
      expect(find.text('Publish to a club'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Club template'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('publish control hides when the viewer has no admin club',
      (tester) async {
    final f = await _fixture('publish_hide_member');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1',
          social: _FakeSocial([_club('c-1', 'Track Club', 'member')]),
          viewerId: 'me'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Publish to a club'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('publish control hides when the viewer is not the author',
      (tester) async {
    final f = await _fixture('publish_hide_nonauthor');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'someone-else'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1',
          social: _FakeSocial([_club('c-1', 'Track Club', 'admin')]),
          viewerId: 'me'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Publish to a club'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the Club template badge shows when club_id is set',
      (tester) async {
    final f = await _fixture('badge');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(_seed(
          _row('r-1', 'Club push day', authorId: 'me', clubId: 'c-1'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1',
          social: _FakeSocial([_club('c-1', 'Track Club', 'admin')]),
          viewerId: 'me'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Club template'), findsOneWidget);
      expect(find.text('Publish to a club'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
