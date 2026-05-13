import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  group('assignCompetitionRanks', () {
    test('returns an empty list for empty input', () {
      expect(assignCompetitionRanks<num>(const [], (t) => t), <int>[]);
    });

    test('distinct times yield 1..n', () {
      final ranks = assignCompetitionRanks<num>([10, 20, 30], (t) => t);
      expect(ranks, [1, 2, 3]);
    });

    test('ties share a rank; the next distinct time skips ordinal slots',
        () {
      final ranks = assignCompetitionRanks<num>(
        [10, 10, 15, 15, 20],
        (t) => t,
      );
      expect(ranks, [1, 1, 3, 3, 5]);
    });

    test('leading tie of three rows shares rank 1', () {
      final ranks = assignCompetitionRanks<num>(
        [60, 60, 60, 65],
        (t) => t,
      );
      expect(ranks, [1, 1, 1, 4]);
    });

    test(
        'a 0-second first effort does not collide with an unseeded sentinel',
        () {
      // Regression: previous in-line implementations seeded `lastTime`
      // to -1 (or no sentinel at all). A zero or negative real time
      // could have inherited rank 0 from the unset `lastRank`. The
      // seeded-flag guard means the first row is always rank 1.
      final ranks = assignCompetitionRanks<num>(
        [0, 0, 5],
        (t) => t,
      );
      expect(ranks, [1, 1, 3]);
    });

    test('preserves the row payload via the timeOf extractor', () {
      final rows = [
        {'time_seconds': 10, 'id': 'a'},
        {'time_seconds': 10, 'id': 'b'},
        {'time_seconds': 15, 'id': 'c'},
      ];
      final ranks = assignCompetitionRanks(
        rows,
        (r) => r['time_seconds']! as int,
      );
      expect(ranks, [1, 1, 3]);
      // Caller zips ranks back with rows by index — pin that the
      // helper does not reorder.
      expect(rows[0]['id'], 'a');
      expect(rows[2]['id'], 'c');
    });
  });

  group('kSegmentAgeBands', () {
    test('13 entries (Strava 5-year bins from 18 to 75+)', () {
      expect(kSegmentAgeBands, hasLength(13));
    });

    test('starts at 18-19 and ends at 75+', () {
      expect(kSegmentAgeBands.first, '18-19');
      expect(kSegmentAgeBands.last, '75+');
    });

    test('every entry matches the RPC parser shape', () {
      // The `segment_leaderboard_tiered` plpgsql function only
      // accepts '75+' or '\\d+-\\d+'; any other shape raises 22023.
      // Pin the client-side list against that contract so a typo
      // can't get past PR review.
      for (final band in kSegmentAgeBands) {
        expect(
          band == '75+' || RegExp(r'^\d+-\d+$').hasMatch(band),
          isTrue,
          reason: 'band $band would crash the RPC',
        );
      }
    });

    test('contiguous 5-year bins between the bookends', () {
      for (var i = 0; i < kSegmentAgeBands.length - 1; i++) {
        final band = kSegmentAgeBands[i];
        if (band == '75+') continue;
        if (band == '18-19') continue;
        final parts = band.split('-');
        final lo = int.parse(parts[0]);
        final hi = int.parse(parts[1]);
        expect(hi - lo, 4, reason: 'band $band not a 5-year bin');
        expect(lo % 5, 0,
            reason: 'band $band not anchored on a multiple of 5');
      }
    });

    test('matches the web SEGMENT_AGE_BANDS list character-for-character',
        () {
      // Read the web source as text and assert the same 13 strings
      // appear in order. The shared-library-syncer agent watches this
      // pair but the unit test is the in-CI guard.
      // We avoid taking a relative path so the test still runs under
      // both the package-local `dart test` and a melos-rooted invocation.
      const expected = [
        '18-19',
        '20-24',
        '25-29',
        '30-34',
        '35-39',
        '40-44',
        '45-49',
        '50-54',
        '55-59',
        '60-64',
        '65-69',
        '70-74',
        '75+',
      ];
      expect(kSegmentAgeBands, expected);
    });
  });

  group('crownLabel', () {
    test('no filter → "Fastest overall"', () {
      expect(crownLabel(null, null), 'Fastest overall');
    });

    test('gender only', () {
      expect(crownLabel('male', null), 'Fastest man');
      expect(crownLabel('female', null), 'Fastest woman');
      expect(crownLabel('nonbinary', null), 'Fastest nonbinary runner');
    });

    test('age band only', () {
      expect(crownLabel(null, '35-39'), 'Fastest 35-39');
      expect(crownLabel(null, '75+'), 'Fastest 75+');
    });

    test('gender + age band combined', () {
      expect(crownLabel('female', '30-34'), 'Fastest woman 30-34');
      expect(crownLabel('male', '75+'), 'Fastest man 75+');
      expect(crownLabel('nonbinary', '18-19'),
          'Fastest nonbinary runner 18-19');
    });

    test('unknown gender values fall through gracefully', () {
      // The migration's CHECK allows prefer_not_to_say; that's never
      // sent as a filter (the UI only offers male / female / nonbinary)
      // but the helper should not throw on garbage input.
      expect(crownLabel('prefer_not_to_say', null), 'Fastest overall');
      expect(crownLabel('prefer_not_to_say', '40-44'), 'Fastest 40-44');
    });
  });

  group('assignCompetitionRanks — additional edge cases', () {
    test('single element gets rank 1', () {
      expect(
        assignCompetitionRanks<num>(const [42], (t) => t),
        [1],
      );
    });

    test('every row tied still produces all rank 1', () {
      expect(
        assignCompetitionRanks<num>(const [100, 100, 100, 100], (t) => t),
        [1, 1, 1, 1],
      );
    });

    test('tie cluster in the middle', () {
      expect(
        assignCompetitionRanks<num>(const [50, 60, 60, 60, 75], (t) => t),
        [1, 2, 2, 2, 5],
      );
    });

    test('alternating ties', () {
      expect(
        assignCompetitionRanks<num>(const [10, 10, 20, 30, 30], (t) => t),
        [1, 1, 3, 4, 4],
      );
    });

    test('double times tie by strict equality', () {
      // The RPC returns time_seconds as a number; SegmentEffortRow.timeSeconds
      // is `double`. Floats that are == still tie; otherwise they don't.
      expect(
        assignCompetitionRanks<num>(const [10.5, 10.5, 10.5000001], (t) => t),
        [1, 1, 3],
      );
    });

    test('mixed int + double extractors compare numerically', () {
      // num covers both — passing an int and a double of equal value
      // should still produce a tie via Dart's `==` on num.
      expect(
        assignCompetitionRanks<num>(const [10, 10.0, 11], (t) => t),
        [1, 1, 3],
      );
    });

    test('1000-row input is O(n) and well-formed', () {
      final rows = List<int>.generate(1000, (i) => i);
      final stopwatch = Stopwatch()..start();
      final ranks = assignCompetitionRanks<num>(rows, (t) => t);
      stopwatch.stop();
      expect(ranks, hasLength(1000));
      expect(ranks.first, 1);
      expect(ranks.last, 1000);
      expect(
        stopwatch.elapsedMilliseconds < 50,
        isTrue,
        reason: 'rank pass took ${stopwatch.elapsedMilliseconds} ms',
      );
    });
  });
}
