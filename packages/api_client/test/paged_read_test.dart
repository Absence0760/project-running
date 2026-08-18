import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Pins the fix for the silent-truncation class in the mobile data layer: a
/// PostgREST SELECT with no `.range()` comes back capped at `db.max-rows`
/// (1000) with a 200 and no flag, so any read whose contract is "every row"
/// was quietly returning only the first page. `fetchRunRowsRaw` is the worst
/// of them — `backup.dart` consumes it as the COMPLETE history, so a
/// 1,400-run account archived 1,000 runs and the restore lost the other 400
/// with no error on either side of the round trip.
void main() {
  /// A fake PostgREST holding [total] rows (values 0..total-1) that answers an
  /// inclusive `[from, to]` range the way the server does: clipped to what
  /// exists, and never more than [serverCap] rows however wide the range.
  ({Future<List<int>> Function(int, int) fetch, List<List<int>> calls}) server(
    int total, {
    int serverCap = 1000,
  }) {
    final calls = <List<int>>[];
    Future<List<int>> fetch(int from, int to) async {
      calls.add([from, to]);
      if (from > total - 1) return const [];
      var last = to < total - 1 ? to : total - 1;
      if (last - from + 1 > serverCap) last = from + serverCap - 1;
      return [for (var i = from; i <= last; i++) i];
    }

    return (fetch: fetch, calls: calls);
  }

  group('readAllPages', () {
    test('1,400 rows are ALL returned, not the first 1,000', () async {
      final s = server(1400);
      final rows = await readAllPages(s.fetch);
      expect(rows.length, 1400,
          reason: 'an unbounded read stops at the 1000-row PostgREST cap; '
              'paging must exhaust the result set');
      expect(rows.first, 0);
      expect(rows.last, 1399);
    });

    test('rows arrive in order across the page boundary with no gap or dupe',
        () async {
      final s = server(2500);
      final rows = await readAllPages(s.fetch);
      expect(rows, List<int>.generate(2500, (i) => i));
      expect(rows.toSet().length, rows.length, reason: 'no duplicated row');
    });

    test('a short first page stops after one request', () async {
      final s = server(12);
      final rows = await readAllPages(s.fetch);
      expect(rows.length, 12);
      expect(s.calls, [
        [0, 999]
      ]);
    });

    test('an exact multiple of the page size takes one extra empty request',
        () async {
      final s = server(2000);
      final rows = await readAllPages(s.fetch);
      expect(rows.length, 2000,
          reason: 'a full last page cannot prove exhaustion on its own');
      expect(s.calls.length, 3);
    });

    test('an empty result set yields no rows', () async {
      final s = server(0);
      expect(await readAllPages(s.fetch), isEmpty);
    });

    test('requests inclusive [from, to] bounds', () async {
      final s = server(5, serverCap: 2);
      await readAllPages(s.fetch, pageSize: 2);
      expect(s.calls, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('errors propagate — a partial archive must never read as complete',
        () async {
      Future<List<int>> boom(int from, int to) async {
        if (from == 0) return List<int>.generate(1000, (i) => i);
        throw StateError('network');
      }

      await expectLater(readAllPages(boom), throwsStateError);
    });

    test('a non-positive page size is rejected', () async {
      await expectLater(
        readAllPages(server(1).fetch, pageSize: 0),
        throwsArgumentError,
      );
    });
  });

  group('the reads whose contract is "every row" are paged', () {
    final src = File('lib/src/api_client.dart').readAsStringSync();

    /// One method's source, from its signature up to the next doc comment.
    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(-1), reason: '$signature not found');
      final next = src.indexOf('\n  /// ', start + signature.length);
      return src.substring(start, next == -1 ? src.length : next);
    }

    for (final m in const [
      'Future<List<Map<String, dynamic>>> fetchRunRowsRaw()',
      'Future<List<RouteReviewRow>> getRouteReviews(',
      'Future<List<EventAttendeeRow>> fetchEventAttendees(',
      'Future<List<CheckpointCrossingRow>> fetchCheckpointCrossings(',
      'Future<List<ExerciseRow>> fetchExerciseCatalogue()',
    ]) {
      test('$m pages', () {
        final b = body(m);
        expect(b.contains('readAllPages'), isTrue,
            reason: '$m is consumed as a complete list; an unbounded SELECT '
                'truncates it at $kPostgrestPageSize rows with no error');
        expect(b.contains('.range(from, to)'), isTrue,
            reason: '$m must ask for an explicit range');
        // A range over an ambiguous order duplicates or drops the row sitting
        // on a page boundary, so every paged read imposes a total order first.
        expect(b.contains('.order('), isTrue,
            reason: '$m must impose a total order before ranging');
      });
    }
  });
}
