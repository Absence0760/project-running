import 'dart:io';

import 'package:test/test.dart';

/// Two source-level guards on `api_client.dart`, in the same file-as-text
/// idiom as `save_run_conflict_target_test.dart` — both cover shapes that
/// only misbehave against a real PostgREST, so a unit test can't observe
/// them any other way.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();

  group('runs upsert never writes a null over server state', () {
    // `RunRow.toJson()` emits all 24 columns including nulls, and an
    // ON CONFLICT DO UPDATE writes those nulls over whatever the server holds.
    // Four of them — is_public, event_id, race_listing_id, concluded_at — are
    // not on the Dart `Run` model at all, so the phone always sends null.
    // A runner shares a run, edits its title offline, and the next batch sync
    // sets is_public back to null: the run leaves `public_runs`, its
    // /share/run/{id} link 404s, and nothing on the phone looks wrong.
    test('a null-stripping body builder exists and strips nulls', () {
      expect(
        src.contains('Map<String, dynamic> _runUpsertBody('),
        isTrue,
        reason: '_runUpsertBody must exist as the one place run bodies are built',
      );
      final start = src.indexOf('Map<String, dynamic> _runUpsertBody(');
      final body = src.substring(start);
      expect(
        body.contains('removeWhere((k, v) => v == null)'),
        isTrue,
        reason: '_runUpsertBody must drop null-valued columns',
      );
    });

    test('both run upsert paths route through it', () {
      // saveRun's single-row path.
      expect(
        src.contains('final json = _runUpsertBody(row.toJson());'),
        isTrue,
        reason: 'saveRun must build its body through _runUpsertBody',
      );
      // saveRunsBatch's per-row map.
      expect(
        src.contains('return _runUpsertBody(RunRow('),
        isTrue,
        reason: 'saveRunsBatch must build each row through _runUpsertBody',
      );
      // And neither may hand a raw toJson() straight to upsert again.
      expect(
        src.contains('upsert(row.toJson())'),
        isFalse,
        reason: 'a raw toJson() upsert reintroduces the null-overwrite',
      );
    });
  });

  group('the live-ping backlog is newest-first under the row cap', () {
    // PostgREST caps a result at 1000 rows. At the broadcaster's 5 s interval
    // that is 83 minutes, so an ascending fetch returns the OLDEST 83 minutes
    // of a long race and omits the runner's current position entirely. Web hit
    // this as issue #334 and pins the same shape in data.test.ts.
    late String query;

    setUp(() {
      final i = src.indexOf("from('live_run_pings')");
      expect(i, greaterThanOrEqualTo(0),
          reason: 'fetchLiveRunPings must still read live_run_pings');
      query = src.substring(i, i + 400 > src.length ? src.length : i + 400);
    });

    test('orders descending, never ascending', () {
      expect(query.contains('ascending: false'), isTrue,
          reason: 'the backlog must be newest-first (issue #334)');
      expect(query.contains('ascending: true'), isFalse,
          reason: 'an ascending backlog fetch is the #334 regression');
    });

    test('caps at 1000 rows', () {
      expect(query.contains('.limit(1000)'), isTrue,
          reason: 'mirror web: an unbounded fetch ships tens of thousands of rows');
    });

    test('replays oldest-first so the newest ping wins the trace', () {
      expect(query.contains('.reversed'), isTrue,
          reason: 'newest-first rows must be reversed before replay');
    });
  });
}
