import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

/// Mirrors the read half of `apps/web/src/lib/segments/effort_rank.test.ts`.
void main() {
  group('readEffortRankRows', () {
    test('indexes the RPC answer by effort id', () {
      final map = readEffortRankRows([
        {'effort_id': 'a', 'rank': 1},
        {'effort_id': 'b', 'rank': 7},
      ]);
      expect(map['a'], 1);
      expect(map['b'], 7);
      expect(map, hasLength(2));
    });

    test('an unanswered effort is absent, not seated at 1', () {
      // The regression this module exists for: `rankByEffort[id] ?? 1` turned
      // "no answer" into a crown — the most flattering claim the chip can
      // make. The map must simply not carry the effort.
      final map = readEffortRankRows([
        {'effort_id': 'a', 'rank': 4},
      ]);
      expect(map.containsKey('b'), isFalse);
      expect(map['b'], isNull);
    });

    test('a non-list response yields an empty map', () {
      for (final bad in <Object?>[null, <String, Object?>{}, 'boom', 7]) {
        expect(readEffortRankRows(bad), isEmpty, reason: '$bad');
      }
    });

    test('a row it cannot use is dropped rather than seated at 1', () {
      final map = readEffortRankRows([
        {'effort_id': 'ok', 'rank': 3},
        {'effort_id': 'no-rank'},
        {'effort_id': 'null-rank', 'rank': null},
        {'effort_id': 'nan-rank', 'rank': double.nan},
        {'effort_id': 'inf-rank', 'rank': double.infinity},
        {'effort_id': 'zero-rank', 'rank': 0},
        {'effort_id': 'negative-rank', 'rank': -1},
        {'effort_id': '', 'rank': 2},
        {'rank': 2},
        null,
        'nonsense',
      ]);
      expect(map, {'ok': 3});
    });

    test('a numeric rank arriving as a string is still read', () {
      // PostgREST serialises `numeric` as a string. `rank` is cast to
      // `integer` in the RPC so it arrives as a number today, but a coercion
      // must never be the thing standing between a real standing and a
      // placeholder.
      expect(readEffortRankRows([
        {'effort_id': 'a', 'rank': '4'},
      ]), {'a': 4});
      expect(readEffortRankRows([
        {'effort_id': 'a', 'rank': 'nonsense'},
      ]), isEmpty);
    });

    test('a fractional rank floors rather than being discarded', () {
      expect(readEffortRankRows([
        {'effort_id': 'a', 'rank': 3.0},
      ]), {'a': 3});
    });
  });
}
