import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-shape tests for the batch auto-match plan prefetch: `saveRunsBatch`
/// must fetch the caller's `training_plans` + `plan_weeks` scope ONCE per
/// batch (not once per run — a bulk Strava import used to re-query the same
/// plans N times) while producing the exact same per-run matches as the
/// per-run path.
///
/// Unlike the live-stack integration tests, this pins the request COUNT,
/// which a real Supabase instance can't observe. The fake sits at the
/// third-party http boundary (allowed by conventions — "mocks for
/// third-party boundaries only"); everything above it (PostgREST builders,
/// ApiClient) is real code.
class _RecordedCall {
  final String method;
  final Uri url;
  final String body;
  _RecordedCall(this.method, this.url, this.body);
}

class _FakeSupabaseHttpClient extends http.BaseClient {
  final List<_RecordedCall> calls = [];
  List<Map<String, dynamic>> plans = [];
  Map<String, List<Map<String, dynamic>>> workoutsByDate = {};

  List<_RecordedCall> byPath(String path, {String? method}) => calls
      .where((c) =>
          c.url.path.contains(path) &&
          (method == null || c.method == method))
      .toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    calls.add(_RecordedCall(request.method, request.url, body));

    Object payload = const <dynamic>[];
    final path = request.url.path;
    if (path.contains('/rest/v1/training_plans') &&
        request.method == 'GET') {
      payload = plans;
    } else if (path.contains('/rest/v1/plan_workouts') &&
        request.method == 'GET') {
      final rawDate = request.url.queryParameters['scheduled_date'] ?? '';
      final date = rawDate.replaceFirst('eq.', '');
      payload = workoutsByDate[date] ?? const <dynamic>[];
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Run _run(String id, DateTime startedAt, double distanceM) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.strava,
    );

void main() {
  late _FakeSupabaseHttpClient fakeHttp;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() async {
    fakeHttp = _FakeSupabaseHttpClient();
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      httpClient: fakeHttp,
    );
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'user-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
    api = ApiClient.withClient(client);
  });

  tearDown(() {
    client.dispose();
  });

  test(
      'saveRunsBatch fetches the plan/week scope once for the whole batch '
      'and matches each run identically to the per-run path', () async {
    fakeHttp.plans = [
      {
        'id': 'plan-1',
        'plan_weeks': [
          {'id': 'week-1'},
        ],
      },
    ];
    fakeHttp.workoutsByDate = {
      // Two open candidates on run-a's date: the closest target within
      // 25% must win (5000 exactly beats 5200).
      '2026-01-05': [
        {
          'id': 'workout-close',
          'target_distance_m': 5000,
          'completed_run_id': null,
          'week_id': 'week-1',
        },
        {
          'id': 'workout-far',
          'target_distance_m': 5200,
          'completed_run_id': null,
          'week_id': 'week-1',
        },
      ],
      // run-c's only candidate is >25% off its 10 km distance: no match.
      '2026-01-07': [
        {
          'id': 'workout-out-of-band',
          'target_distance_m': 30000,
          'completed_run_id': null,
          'week_id': 'week-1',
        },
      ],
    };

    final failures = await api.saveRunsBatch([
      _run('run-a', DateTime.utc(2026, 1, 5, 9), 5000),
      _run('run-b', DateTime.utc(2026, 1, 6, 9), 8000),
      _run('run-c', DateTime.utc(2026, 1, 7, 9), 10000),
    ]);
    expect(failures, isEmpty);

    expect(
      fakeHttp.byPath('/rest/v1/training_plans', method: 'GET'),
      hasLength(1),
      reason: 'the plan/week scope is batch-invariant — a 3-run batch must '
          'fetch training_plans exactly once, not once per run',
    );
    expect(
      fakeHttp.byPath('/rest/v1/plan_workouts', method: 'GET'),
      hasLength(3),
      reason: 'the per-run candidate query still runs for every run',
    );

    final patches = fakeHttp.byPath('/rest/v1/plan_workouts', method: 'PATCH');
    expect(patches, hasLength(1),
        reason: 'only run-a has an in-band candidate');
    expect(patches.single.url.queryParameters['id'], 'eq.workout-close',
        reason: 'closest target distance within 25% wins');
    final patchBody = jsonDecode(patches.single.body) as Map<String, dynamic>;
    expect(patchBody['completed_run_id'], 'run-a');
    expect(patchBody['manually_completed'], false);
  });

  test('a batch for a user with no plans skips the candidate queries',
      () async {
    fakeHttp.plans = [];

    await api.saveRunsBatch([
      _run('run-a', DateTime.utc(2026, 1, 5, 9), 5000),
      _run('run-b', DateTime.utc(2026, 1, 6, 9), 8000),
    ]);

    expect(fakeHttp.byPath('/rest/v1/training_plans', method: 'GET'),
        hasLength(1));
    expect(fakeHttp.byPath('/rest/v1/plan_workouts'), isEmpty,
        reason: 'no plan weeks means no run can match — same early return '
            'the per-run path takes');
  });

  test('standalone autoMatchRunToPlanWorkout still fetches its own scope',
      () async {
    fakeHttp.plans = [
      {
        'id': 'plan-1',
        'plan_weeks': [
          {'id': 'week-1'},
        ],
      },
    ];
    fakeHttp.workoutsByDate = {
      '2026-01-05': [
        {
          'id': 'workout-close',
          'target_distance_m': 5000,
          'completed_run_id': null,
          'week_id': 'week-1',
        },
      ],
    };

    final matched = await api.autoMatchRunToPlanWorkout(
        'run-a', DateTime.utc(2026, 1, 5, 9), 5000);

    expect(matched, 'workout-close');
    expect(fakeHttp.byPath('/rest/v1/training_plans', method: 'GET'),
        hasLength(1));
  });
}
