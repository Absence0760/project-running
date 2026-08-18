import 'dart:io';

import 'package:api_client/api_client.dart';
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
        {SocialService? social, String? viewerId, ApiClient? api}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RoutineDetailScreen(
          api: api,
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

class _HistoryApi extends ApiClient {
  _HistoryApi({this.aggregate, this.throwUntilCall = 0});

  final Map<String, dynamic>? aggregate;
  final int throwUntilCall;
  int calls = 0;
  int? lastRecentLimit;

  @override
  Future<Map<String, dynamic>> fetchGymRoutineHistory(
    String routineId, {
    int recentLimit = 5,
  }) async {
    calls++;
    lastRecentLimit = recentLimit;
    if (calls <= throwUntilCall) throw StateError('offline');
    return aggregate ?? _aggregate(const []);
  }
}

Map<String, dynamic> _session(String id, String startedAt,
        {String? title, Object? metadata}) =>
    <String, dynamic>{
      'id': id,
      'started_at': startedAt,
      'title': title,
      'metadata': metadata ?? <String, dynamic>{},
    };

/// One `gym_routine_history` row. The tallies default to what the RPC would
/// report for exactly these rows, so a case that only cares about rendering
/// doesn't have to restate them; a case about the count outrunning the page
/// overrides them.
Map<String, dynamic> _aggregate(
  List<Map<String, dynamic>> recent, {
  int? sessionCount,
  String? lastPerformedAt,
  int? gradedCount,
  int? completedCount,
}) {
  const graded = {'completed', 'partial', 'abandoned'};
  final performed = [
    for (final r in recent)
      if ((r['metadata'] as Map?)?['gym_session_draft'] is! Map) r,
  ]..sort((a, b) =>
      (b['started_at'] as String).compareTo(a['started_at'] as String));
  final verdicts = [
    for (final r in performed) (r['metadata'] as Map?)?['gym_adherence'],
  ];
  return <String, dynamic>{
    'session_count': sessionCount ?? performed.length,
    'last_performed_at': lastPerformedAt ??
        (performed.isEmpty ? null : performed.first['started_at']),
    'graded_count':
        gradedCount ?? verdicts.where(graded.contains).length,
    'completed_count':
        completedCount ?? verdicts.where((v) => v == 'completed').length,
    'recent_sessions': recent,
  };
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
        {String? authorId, String? clubId, bool isPublic = false}) =>
    <String, dynamic>{
      'id': id,
      'author_id': authorId,
      'club_id': clubId,
      'is_public_template': isPublic,
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

  testWidgets('public publish row shows for the author of a personal routine',
      (tester) async {
    final f = await _fixture('public_show');
    try {
      await tester.runAsync(() =>
          f.store.replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1', viewerId: 'me'));
      await tester.pump();
      expect(find.text('Publish to public library'), findsOneWidget);
      expect(find.text('In the public library'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('public badge + unpublish action show when already public',
      (tester) async {
    final f = await _fixture('public_badge');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'me', isPublic: true))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1', viewerId: 'me'));
      await tester.pump();
      expect(find.text('In the public library'), findsOneWidget);
      expect(find.text('Remove from public library'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('public publish row hides for a non-author', (tester) async {
    final f = await _fixture('public_hide_nonauthor');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'someone-else'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1', viewerId: 'me'));
      await tester.pump();
      expect(find.text('Publish to public library'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('public publish row hides on a club-owned routine',
      (tester) async {
    final f = await _fixture('public_hide_club');
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'me', clubId: 'c-1'))));
      await tester.pumpWidget(_app(f.store, f.gym, 'r-1', viewerId: 'me'));
      await tester.pump();
      expect(find.text('Publish to public library'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('past sessions render as the routine history panel',
      (tester) async {
    final f = await _fixture('history_render');
    final now = DateTime.now().toUtc();
    final api = _HistoryApi(
        aggregate: _aggregate([
      _session('w-1', now.subtract(const Duration(days: 2)).toIso8601String(),
          title: 'Push day A', metadata: {'gym_adherence': 'completed'}),
      _session('w-2', now.subtract(const Duration(days: 9)).toIso8601String(),
          metadata: {'gym_adherence': 'partial'}),
      _session('w-3', now.subtract(const Duration(days: 16)).toIso8601String(),
          metadata: {'routine_id': 'r-1'}),
    ]));
    try {
      await tester.runAsync(() => f.store
          .replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      expect(find.text('Routine history'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget);
      // Only the two graded sessions reach the rate denominator.
      expect(find.text('Done 2 days ago  ·  1 of 2 completed'), findsOneWidget);
      expect(find.text('Recent sessions'), findsOneWidget);
      expect(find.text('Push day A'), findsOneWidget);
      expect(find.text('Untitled workout'), findsNWidgets(2));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Partly done'), findsOneWidget);
      expect(find.text('Not graded'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('an in-flight draft session is not counted as performed',
      (tester) async {
    final f = await _fixture('history_draft');
    final now = DateTime.now().toUtc();
    final api = _HistoryApi(
        aggregate: _aggregate([
      _session('draft', now.toIso8601String(), metadata: {
        'routine_id': 'r-1',
        'gym_session_draft': {'saved_at': now.toIso8601String(), 'results': []},
      }),
      _session('done', now.subtract(const Duration(days: 1)).toIso8601String(),
          title: 'Push day A', metadata: {'gym_adherence': 'completed'}),
    ]));
    try {
      await tester.runAsync(() => f.store
          .replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      expect(find.text('1 session'), findsOneWidget);
      expect(find.text('Done yesterday  ·  1 of 1 completed'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the count is the aggregate while the list stays a bounded page',
      (tester) async {
    final f = await _fixture('history_paged');
    final now = DateTime.now().toUtc();
    final api = _HistoryApi(
        aggregate: _aggregate([
          for (var i = 0; i < 5; i++)
            _session('w-$i', now.subtract(Duration(days: i + 1)).toIso8601String(),
                metadata: {'gym_adherence': 'completed'}),
        ],
            sessionCount: 812,
            gradedCount: 800,
            completedCount: 600));
    try {
      await tester.runAsync(() => f.store
          .replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      // The panel renders five rows but must claim the server's complete
      // total, not the length of the page it happens to hold.
      expect(find.text('812 sessions'), findsOneWidget);
      expect(find.text('Done yesterday  ·  600 of 800 completed'),
          findsOneWidget);
      expect(find.text('Untitled workout'), findsNWidgets(5));
      // The page it asked for is exactly the page it lists.
      expect(api.lastRecentLimit, 5);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a routine never run renders no history panel', (tester) async {
    final f = await _fixture('history_empty');
    final api = _HistoryApi();
    try {
      await tester.runAsync(() => f.store
          .replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      expect(find.text('Routine history'), findsNothing);
      expect(find.text('Couldn’t load this routine’s history.'),
          findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a failed history read shows a retry, and the retry recovers',
      (tester) async {
    final f = await _fixture('history_error');
    final now = DateTime.now().toUtc();
    final api = _HistoryApi(
        throwUntilCall: 1,
        aggregate: _aggregate([
          _session('w-1', now.toIso8601String(),
              title: 'Push day A', metadata: {'gym_adherence': 'completed'}),
        ]));
    try {
      await tester.runAsync(() => f.store
          .replaceFromServer(_seed(_row('r-1', 'Push day', authorId: 'me'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      expect(find.text('Couldn’t load this routine’s history.'),
          findsOneWidget);
      expect(find.text('Routine history'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(api.calls, 2);
      expect(find.text('Couldn’t load this routine’s history.'),
          findsNothing);
      expect(find.text('Routine history'), findsOneWidget);
      expect(find.text('Done today  ·  1 of 1 completed'), findsOneWidget);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the history panel is not read for a non-author', (tester) async {
    final f = await _fixture('history_nonauthor');
    final now = DateTime.now().toUtc();
    final api = _HistoryApi(
        aggregate: _aggregate([
      _session('w-1', now.toIso8601String(),
          metadata: {'gym_adherence': 'completed'}),
    ]));
    try {
      await tester.runAsync(() => f.store.replaceFromServer(
          _seed(_row('r-1', 'Push day', authorId: 'someone-else'))));
      await tester.pumpWidget(
          _app(f.store, f.gym, 'r-1', viewerId: 'me', api: api));
      await tester.pump();
      await tester.pump();

      expect(api.calls, 0);
      expect(find.text('Routine history'), findsNothing);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
