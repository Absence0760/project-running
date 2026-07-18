@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-level integration tests for `ApiClient` priority methods —
/// `signIn` / `getRuns` / `fetchTrack` / `saveRun` (which transitively
/// exercises `_uploadTrack`).
///
/// **Skipped unless `SUPABASE_TEST_URL` is set.** These tests need a
/// live local Supabase stack on the URL pointed to by the env vars
/// below, with the project's `seed.sql` applied (`supabase db reset
/// --local` from `apps/backend`). The seed user `runner@test.com /
/// testtest` is the fixture: 12 runs, 5 routes, two connected
/// integrations.
///
/// Run locally with:
/// ```
/// cd apps/backend && supabase status -o env
/// # …
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY from `supabase status`>
/// cd ../../packages/api_client
/// flutter test test/api_client_integration_test.dart
/// ```
///
/// Why integration tests rather than mocktail mocks: the methods under
/// test are predominantly chained PostgREST + Storage builder calls
/// (`_client.from(...).upsert(...)`, `_client.storage.from(...)
/// .upload(...)`). Mocking the fluent surface end-to-end is verbose
/// enough that the test would mostly assert "we called the methods
/// in this order" rather than "the wire shape is correct" — i.e.
/// re-implementing the methods inside the mock. Real Supabase is the
/// authoritative fixture (cf. docs/testing/testing.md "No mocks for databases
/// we control").
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');

void main() {
  // The env-var indirection through `String.fromEnvironment` means
  // these are baked in at compile time when `--dart-define` is used.
  // The Platform.environment fallback covers the shell-export path,
  // which is what the local-dev recipe above uses.
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'ApiClient integration tests — skipped (SUPABASE_TEST_URL not set)',
      () {
        // Intentional no-op. CI without a Supabase stack still sees a
        // passing test; locally with the env vars set, the real tests
        // below run.
      },
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run '
          'these tests against a local Supabase (see file header).',
    );
    return;
  }

  group('ApiClient — wire-level integration (real local Supabase)', () {
    late SupabaseClient client;
    late ApiClient api;
    String? userId;
    final inserted = <String>[];

    setUp(() async {
      // Each test gets a fresh SupabaseClient so the auth state of one
      // test never bleeds into the next (the GoTrue client owns a
      // session that's per-instance, not per-test).
      client = SupabaseClient(url, anonKey);
      api = ApiClient.withClient(client);
      userId = await api.signIn(email: 'runner@test.com', password: 'testtest');
    });

    tearDown(() async {
      // Clean up any rows the test inserted before signing out, so
      // the seed user's row count stays stable across runs.
      for (final runId in inserted) {
        try {
          await api.deleteRunById(runId);
        } catch (_) {
          // Best-effort. If the row's already gone, that's fine.
        }
      }
      inserted.clear();
      try {
        await api.signOut();
      } catch (_) {}
      client.dispose();
    });

    test('signIn returns the seed user id', () {
      // signIn ran in setUp; just assert the returned value.
      expect(userId, isNotNull);
      expect(userId, isA<String>());
      expect(userId!.length, greaterThan(8));
    });

    test(
        'autoMatchRunToPlanWorkout links a run to a same-date workout '
        'within 25% of target distance, and skips one that is further',
        () async {
      // Client-side mirror of the web `autoMatchRunToPlanWorkout` (there is
      // no `auto_match_run_to_plan_workout` RPC). A real run id satisfies
      // the plan_workouts.completed_run_id FK.
      final runId = (await api.getRuns()).first.id;

      // plan -> week -> two workouts on far-future dates so no seeded
      // workout interferes; the plan cascade-deletes weeks + workouts.
      final plan = await client
          .from('training_plans')
          .insert({
            'user_id': userId,
            'name': 'auto-match integration plan',
            'goal_event': 'distance_5k',
            'goal_distance_m': 5000,
            'start_date': '2099-06-01',
            'end_date': '2099-08-31',
            // Non-active so it doesn't trip training_plans_one_active; the
            // auto-match query is status-agnostic (mirrors web).
            'status': 'completed',
          })
          .select('id')
          .single();
      final planId = plan['id'] as String;
      addTearDown(() async {
        try {
          await client.from('training_plans').delete().eq('id', planId);
        } catch (_) {}
      });

      final week = await client
          .from('plan_weeks')
          .insert({'plan_id': planId, 'week_index': 1})
          .select('id')
          .single();
      final weekId = week['id'] as String;

      final matchWo = await client
          .from('plan_workouts')
          .insert({
            'week_id': weekId,
            'scheduled_date': '2099-06-15',
            'kind': 'easy',
            'target_distance_m': 5000,
          })
          .select('id')
          .single();
      final matchWoId = matchWo['id'] as String;

      final missWo = await client
          .from('plan_workouts')
          .insert({
            'week_id': weekId,
            'scheduled_date': '2099-06-16',
            'kind': 'easy',
            'target_distance_m': 20000,
          })
          .select('id')
          .single();
      final missWoId = missWo['id'] as String;

      // 5000 m run on the matching date -> links to matchWo.
      final matched = await api.autoMatchRunToPlanWorkout(
          runId, DateTime.utc(2099, 6, 15), 5000.0);
      expect(matched, matchWoId,
          reason: 'a same-date run within 25% of target distance must '
              'auto-link to that workout');
      final linked = await client
          .from('plan_workouts')
          .select('completed_run_id, manually_completed, completed_at')
          .eq('id', matchWoId)
          .single();
      expect(linked['completed_run_id'], runId);
      expect(linked['manually_completed'], isFalse,
          reason: 'auto-match is not a manual completion');
      expect(linked['completed_at'], isNotNull);

      // 5000 m run on the off-distance date -> no match (20000 m target is
      // 75% away), workout stays open.
      final unmatched = await api.autoMatchRunToPlanWorkout(
          runId, DateTime.utc(2099, 6, 16), 5000.0);
      expect(unmatched, isNull,
          reason: 'a run > 25% from every same-date target must not link');
      final stillOpen = await client
          .from('plan_workouts')
          .select('completed_run_id')
          .eq('id', missWoId)
          .single();
      expect(stillOpen['completed_run_id'], isNull);
    });

    test('getRuns returns the seeded runs for runner@test.com', () async {
      final runs = await api.getRuns();
      // seed.sql provisions exactly 12 runs for this user.
      expect(runs.length, greaterThanOrEqualTo(12));
      // Tracks are NOT eagerly loaded — dashboard list never wants them.
      // Pin that contract.
      expect(runs.first.track, isEmpty,
          reason: 'getRuns must return Run objects with empty track; '
              'callers download via fetchTrack on demand.');
      // Newest-first ordering pinned by the api_client comment.
      for (var i = 1; i < runs.length; i++) {
        expect(
          runs[i].startedAt.isAtSameMomentAs(runs[i - 1].startedAt) ||
              runs[i].startedAt.isBefore(runs[i - 1].startedAt),
          isTrue,
          reason: 'getRuns must return rows newest-first by startedAt',
        );
      }
    });

    test(
        'fetchRoutesIntersectingTrack returns the matching seeded route '
        'for a track that overlaps it', () async {
      // Pick a known seeded route ("Commute Run", id is stable). Use
      // its waypoints to construct an overlapping track — endpoints
      // exactly on the route's start/end so startOffsetM + endOffsetM
      // should be ~0 and the route appears as a candidate.
      final commute = await client
          .from('routes')
          .select('id, waypoints, distance_m')
          .eq('name', 'Commute Run')
          .eq('user_id', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')
          .single();
      final waypointsJson = commute['waypoints'] as List;
      final track = [
        for (final w in waypointsJson)
          Waypoint(
            lat: ((w as Map)['lat'] as num).toDouble(),
            lng: (w['lng'] as num).toDouble(),
          ),
      ];
      expect(track.length, greaterThanOrEqualTo(2),
          reason: 'seeded Commute Run must have at least 2 waypoints '
              'for the RPC to accept it');

      final candidates = await api.fetchRoutesIntersectingTrack(track);
      expect(candidates, isNotEmpty,
          reason: 'a track that retraces the seeded Commute Run must '
              'surface at least one candidate via the spatial RPC');
      final hit = candidates.firstWhere(
        (c) => c.id == commute['id'],
        orElse: () => throw StateError(
            'Commute Run not in the candidate list — the spatial RPC '
            'index may be stale, or routes.geom was never populated '
            'for the seed row.'),
      );
      // Endpoint offsets should be tiny (we used the same start/end
      // coordinates as the route) and the length ratio should be ~0.
      expect(hit.startOffsetM, lessThan(50),
          reason: 'recorded start sits within metres of the route\'s '
              'start; offset must be small');
      expect(hit.endOffsetM, lessThan(50),
          reason: 'recorded end sits within metres of the route\'s '
              'end; offset must be small');
    });

    test('fetchRoutesIntersectingTrack returns empty for a track far '
        'from any seeded route', () async {
      // Mid-Atlantic — no seeded route is here.
      final track = [
        const Waypoint(lat: 0, lng: -30),
        const Waypoint(lat: 0.001, lng: -30.001),
      ];
      final candidates = await api.fetchRoutesIntersectingTrack(track);
      expect(candidates, isEmpty,
          reason: 'a track in the middle of the ocean must not surface '
              'any of the seeded routes (Sydney + London)');
    });

    test(
        'fetchRoutesIntersectingTrack short-circuits on a single-point '
        'track', () async {
      // Implementation drops tracks with length < 2 without calling
      // the RPC — important so the recorder\'s indoor-mode first
      // snapshot (which has a single point or none) doesn\'t fire a
      // wasted network call.
      final track = [const Waypoint(lat: 47.37, lng: 8.54)];
      final candidates = await api.fetchRoutesIntersectingTrack(track);
      expect(candidates, isEmpty);
    });

    test('saveRun + fetchTrack round-trip through Storage and the '
        'runs row (exercises _uploadTrack + fetchTrack)', () async {
      // The integration roundtrip pins three guarantees in one shot:
      //   1. saveRun persists the row (visible via getRuns).
      //   2. _uploadTrack uploads gzipped JSON bytes the runs bucket
      //      accepts (migration 20260815_001 mime allowlist — the
      //      contentType must be `application/gzip`, not
      //      `application/json`; the wrong one 415s silently).
      //   3. fetchTrack decodes the same payload back to the same
      //      waypoints.
      //
      // The seed runs in seed.sql set `track_url` to the canonical
      // path-shape (to exercise the path-shape CHECK constraint test)
      // but DON'T upload an actual file — a standalone fetchTrack
      // test against a seed run would 404 against the Storage object,
      // not the code under test. Generating + saving our own run
      // sidesteps that.
      // Build a tiny but real Run with a 3-point track. The
      // _uploadTrack path serialises this to gzipped JSON and writes
      // it to the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`.
      final id = '00000000-0000-0000-0000-' + DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);
      final run = Run(
        id: id,
        startedAt: DateTime.now().toUtc(),
        duration: const Duration(minutes: 25),
        distanceMetres: 5000,
        track: const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.56),
        ],
        source: RunSource.app,
        // Required by `runs_metadata_activity_type_check` (migration
        // 20260601_001) — every row needs a non-empty
        // `metadata.activity_type`. Production mobile callsites
        // (add_run_screen, run_screen) populate it; the test must
        // too.
        metadata: const {'activity_type': 'run'},
      );
      inserted.add(id);

      await api.saveRun(run);

      // Read it back via getRuns and confirm the track is downloadable.
      final all = await api.getRuns(limit: 100);
      final saved = all.where((r) => r.id == id).toList();
      expect(saved, hasLength(1),
          reason: 'saveRun must persist a row visible to the same '
              'user via getRuns.');
      expect(saved.first.distanceMetres, 5000);
      expect(saved.first.duration, const Duration(minutes: 25));

      // The track url is in metadata['track_url'] after _runFromRow's
      // synthesised stash (see CLAUDE.md "Run.metadata is a jsonb
      // bag"). Use fetchTrack to verify the Storage upload landed.
      final downloaded = await api.fetchTrack(saved.first);
      expect(downloaded, hasLength(3),
          reason: 'fetchTrack must return the 3 waypoints that '
              'saveRun uploaded to Storage.');
      expect(downloaded.first.lat, closeTo(47.37, 0.001));
      expect(downloaded.last.lng, closeTo(8.56, 0.001));
    });

    test('getRuns(updatedSince:) delta filter matches metadata.last_modified_at',
        () async {
      // Regression: the PostgREST filter key was written as
      // `metadata->>'last_modified_at'` — the quoted key is treated as a
      // literal JSON key named `'last_modified_at'` (quotes included),
      // which matches nothing, so EVERY delta pull silently returned []
      // and multi-device edits never arrived after the cold load.
      final id = '00000000-0000-0000-0001-' + DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);
      final stamp = DateTime.now().toUtc();
      final run = Run(
        id: id,
        startedAt: stamp,
        duration: const Duration(minutes: 30),
        distanceMetres: 6000,
        track: const [],
        source: RunSource.app,
        metadata: {
          'activity_type': 'run',
          'last_modified_at': stamp.toIso8601String(),
        },
      );
      inserted.add(id);
      await api.saveRun(run);

      final since = stamp.subtract(const Duration(minutes: 1));
      final delta = await api.getRuns(limit: 200, updatedSince: since);
      expect(delta.map((r) => r.id), contains(id),
          reason: 'a run stamped after `updatedSince` must be returned '
              'by the delta pull.');

      final afterStamp = stamp.add(const Duration(minutes: 1));
      final none = await api.getRuns(limit: 200, updatedSince: afterStamp);
      expect(none.map((r) => r.id), isNot(contains(id)),
          reason: 'a run stamped before `updatedSince` must be excluded.');
    });

    test(
        'fetchPublicProfile stays within the user_profiles column grant '
        '(no 42501)', () async {
      // Regression for "Could not load profile.": `user_profiles` is
      // locked to column-level SELECT grants for authenticated/anon
      // (id, display_name, avatar_url, created_at). `preferred_unit`
      // (20260810_001), `subscription_tier`/`subscription_at`/
      // `parkrun_number` (20260707_001) are revoked. PostgREST rejects
      // the WHOLE read with 42501 "permission denied for table
      // user_profiles" if the select names any revoked column, which
      // tanks the entire profile screen. A live read against real
      // grants is the only thing that catches a select drifting back
      // onto a revoked column — assert it succeeds and returns the row.
      final profile = await api.fetchPublicProfile(userId!);
      expect(profile, isNotNull,
          reason: 'fetchPublicProfile must succeed for the seed user; a '
              '42501 here means the select names a column revoked from '
              'the authenticated grant (e.g. preferred_unit).');
      expect(profile!.id, userId);
      expect(profile.displayName, isNotEmpty);
    });

    test(
        'fetchFollowing / fetchFollowers stay within the user_profiles '
        'column grant (no 42501)', () async {
      // Regression for "Could not load feed.": both helpers hydrated
      // follow edges with a bare select() on user_profiles, which
      // requests revoked columns and 42501s — killing the whole feed
      // (fetchFollowing is inside the feed's Future.wait) and the
      // profile Followers/Following tabs. The seed user follows two
      // accounts, so a successful narrowed read returns both.
      final following = await api.fetchFollowing(userId!);
      expect(following, hasLength(greaterThanOrEqualTo(2)),
          reason: 'fetchFollowing must succeed for the seed user; a '
              '42501 here means the profile hydrate drifted back onto '
              'a revoked user_profiles column.');
      expect(following.first.displayName, isNotEmpty);
      final followers = await api.fetchFollowers(userId!);
      expect(followers, isNotNull);
    });

    test('fetchProfileSummary loads for the seed user (profile screen '
        'entry path)', () async {
      // fetchProfileSummary fans out to fetchPublicProfile +
      // fetchFollowCounts + viewerFollows; it is the first of the six
      // parallel calls the profile screen awaits, and a throw in any
      // of them collapses the whole screen to "Could not load profile."
      // Pin the happy path end-to-end against real grants.
      final summary = await api.fetchProfileSummary(userId!);
      expect(summary, isNotNull);
      expect(summary!.id, userId);
      expect(summary.displayName, isNotEmpty);
    });
  });

  // Offline-create idempotency (issue #365). Every `create*` method backing an
  // OfflineSyncStore pushCreate is replayed verbatim by the drain loop when a
  // first attempt committed server-side but its HTTP response was lost — the
  // store still sees the row as pendingCreate. Before the fix these used
  // `.insert()`, so the replay unique-violated on the client-minted PK, the
  // catch left the row pendingCreate forever, and (for gym workouts) a workout
  // whose ack was lost before its sets landed stuck with zero sets. These
  // tests replay each create and assert the second call no-ops rather than
  // duplicating the parent or its children.
  group('offline-create idempotency — a lost-ack retry no-ops (issue #365)',
      () {
    late SupabaseClient client;
    late ApiClient api;
    String? userId;
    final cleanup = <Future<void> Function()>[];

    setUp(() async {
      client = SupabaseClient(url, anonKey);
      api = ApiClient.withClient(client);
      userId = await api.signIn(email: 'runner@test.com', password: 'testtest');
    });

    tearDown(() async {
      for (final del in cleanup.reversed) {
        try {
          await del();
        } catch (_) {}
      }
      cleanup.clear();
      try {
        await api.signOut();
      } catch (_) {}
      client.dispose();
    });

    final rand = Random();
    String hex(int n) => List.generate(
        n, (_) => rand.nextInt(16).toRadixString(16)).join();
    String uuid() => '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + rand.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';

    Future<int> countIn(String table, String col, String value) async {
      final rows = await client.from(table).select('id').eq(col, value);
      return (rows as List).length;
    }

    test('createGear replays idempotently', () async {
      final id = uuid();
      cleanup.add(() => api.deleteGear(id));
      await api.createGear(id: id, kind: 'shoe', name: 'Idem trainers');
      await api.createGear(id: id, kind: 'shoe', name: 'Idem trainers');
      expect(await countIn('gear', 'id', id), 1,
          reason: 'the lost-ack replay must not create a second gear row');
    });

    test('logFood replays idempotently', () async {
      final id = uuid();
      cleanup.add(() => api.deleteFoodLog(id));
      final at = DateTime.now().toUtc();
      await api.logFood(id: id, startedAt: at, itemName: 'Idem oats');
      await api.logFood(id: id, startedAt: at, itemName: 'Idem oats');
      expect(await countIn('food_log', 'id', id), 1,
          reason: 'the lost-ack replay must not create a second food row');
    });

    test('createGymWorkout replays idempotently and keeps its sets', () async {
      final id = uuid();
      cleanup.add(() => api.deleteGymWorkout(id));
      final at = DateTime.now().toUtc();
      final sets = <GymSetInput>[
        (
          exerciseName: 'Squat',
          reps: 5,
          weightKg: 100,
          rpe: null,
          setType: null,
          durationS: null,
          exerciseId: null,
        ),
        (
          exerciseName: 'Squat',
          reps: 5,
          weightKg: 105,
          rpe: null,
          setType: null,
          durationS: null,
          exerciseId: null,
        ),
      ];
      await api.createGymWorkout(id: id, startedAt: at, sets: sets);
      await api.createGymWorkout(id: id, startedAt: at, sets: sets);
      expect(await countIn('gym_workouts', 'id', id), 1,
          reason: 'the replay must not create a second workout');
      expect(await countIn('gym_sets', 'workout_id', id), 2,
          reason: 'the replay must not duplicate the sets');
    });

    test(
        'createGymWorkout populates sets on a retry when the first ack was '
        'lost before the sets landed (zero-set recovery)', () async {
      // Simulate the worst case the issue calls out: the workout INSERT
      // committed but the connection dropped before `_replaceGymSets`, so
      // the server holds a set-less workout. The drain replays the create.
      final id = uuid();
      cleanup.add(() => api.deleteGymWorkout(id));
      final at = DateTime.now().toUtc();
      await client.from('gym_workouts').insert({
        'id': id,
        'user_id': userId,
        'started_at': at.toIso8601String(),
      });
      expect(await countIn('gym_sets', 'workout_id', id), 0,
          reason: 'precondition: the partially-committed workout has no sets');
      await api.createGymWorkout(id: id, startedAt: at, sets: <GymSetInput>[
        (
          exerciseName: 'Bench',
          reps: 8,
          weightKg: 60,
          rpe: null,
          setType: null,
          durationS: null,
          exerciseId: null,
        ),
      ]);
      expect(await countIn('gym_workouts', 'id', id), 1);
      expect(await countIn('gym_sets', 'workout_id', id), 1,
          reason: 'the retry must reach the sets step, not leave it zero-set');
    });

    test('createGymRoutine replays idempotently (no duplicate exercises/sets)',
        () async {
      final id = uuid();
      cleanup.add(() => api.deleteGymRoutine(id));
      final exercises = <GymRoutineExerciseInput>[
        (
          exerciseName: 'Deadlift',
          exerciseKey: 'deadlift',
          supersetGroup: null,
          supersetOrder: null,
          modality: null,
          progression: null,
          progressionParams: null,
          sets: <GymRoutineSetInput>[
            (
              setType: null,
              targetRepsMin: 5,
              targetRepsMax: null,
              targetWeightKg: 140,
              targetRpe: null,
              restS: null,
              targetDurationS: null,
              targetDistanceM: null,
            ),
            (
              setType: null,
              targetRepsMin: 5,
              targetRepsMax: null,
              targetWeightKg: 140,
              targetRpe: null,
              restS: null,
              targetDurationS: null,
              targetDistanceM: null,
            ),
          ],
        ),
      ];
      await api.createGymRoutine(id: id, title: 'Idem routine', exercises: exercises);
      await api.createGymRoutine(id: id, title: 'Idem routine', exercises: exercises);
      expect(await countIn('gym_routines', 'id', id), 1);
      final exRows = await client
          .from('gym_routine_exercises')
          .select('id')
          .eq('routine_id', id);
      expect((exRows as List), hasLength(1),
          reason: 'the replay must not duplicate the routine exercises');
      final exId = (exRows.first as Map)['id'] as String;
      expect(await countIn('gym_routine_sets', 'routine_exercise_id', exId), 2,
          reason: 'the replay must not duplicate the routine sets');
    });

    test('createMealTemplate replays idempotently (no duplicate items)',
        () async {
      final id = uuid();
      cleanup.add(() => api.deleteMealTemplate(id));
      final items = <MealTemplateItemInput>[
        (
          itemName: 'Eggs',
          mealSlot: null,
          calories: 150,
          proteinG: 12,
          carbsG: 1,
          fatG: 10,
          externalId: null,
        ),
        (
          itemName: 'Toast',
          mealSlot: null,
          calories: 90,
          proteinG: 3,
          carbsG: 18,
          fatG: 1,
          externalId: null,
        ),
      ];
      await api.createMealTemplate(id: id, name: 'Idem breakfast', items: items);
      await api.createMealTemplate(id: id, name: 'Idem breakfast', items: items);
      expect(await countIn('meal_templates', 'id', id), 1);
      expect(await countIn('meal_template_items', 'template_id', id), 2,
          reason: 'the replay must not duplicate the template items');
    });

    test('createRecipe replays idempotently (no duplicate ingredients)',
        () async {
      final id = uuid();
      cleanup.add(() => api.deleteRecipe(id));
      final ingredients = <RecipeIngredientInput>[
        (
          itemName: 'Rice',
          quantity: 1,
          calories: 200,
          proteinG: 4,
          carbsG: 44,
          fatG: 1,
          externalId: null,
        ),
        (
          itemName: 'Chicken',
          quantity: 1,
          calories: 165,
          proteinG: 31,
          carbsG: 0,
          fatG: 4,
          externalId: null,
        ),
      ];
      await api.createRecipe(id: id, name: 'Idem bowl', ingredients: ingredients);
      await api.createRecipe(id: id, name: 'Idem bowl', ingredients: ingredients);
      expect(await countIn('recipes', 'id', id), 1);
      expect(await countIn('recipe_ingredients', 'recipe_id', id), 2,
          reason: 'the replay must not duplicate the recipe ingredients');
    });

    test('createSessionPlan replays idempotently (no duplicate blocks/items)',
        () async {
      final id = uuid();
      cleanup.add(() => api.deleteSessionPlan(id));
      final blockId = uuid();
      final itemId = uuid();
      final blocks = <SessionPlanBlockInput>[
        (id: blockId, position: 0, name: 'Warm-up'),
      ];
      final items = <SessionPlanItemInput>[
        (
          id: itemId,
          blockId: blockId,
          position: 0,
          movementName: 'Cat-cow',
          kind: 'reps',
          durationS: null,
          reps: 10,
          perSide: false,
          tempo: null,
          cue: null,
        ),
      ];
      await api.createSessionPlan(
          id: id, title: 'Idem flow', blocks: blocks, items: items);
      await api.createSessionPlan(
          id: id, title: 'Idem flow', blocks: blocks, items: items);
      expect(await countIn('session_plans', 'id', id), 1);
      expect(await countIn('session_plan_blocks', 'plan_id', id), 1,
          reason: 'the replay must not duplicate the plan blocks');
      expect(await countIn('session_plan_items', 'plan_id', id), 1,
          reason: 'the replay must not duplicate the plan items');
    });
  });
}
