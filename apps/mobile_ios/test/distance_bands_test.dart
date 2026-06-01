import 'package:flutter_test/flutter_test.dart';

import '../lib/distance_bands.dart';

void main() {
  group('bandForDistance', () {
    test('maps nominal race distances to their band', () {
      expect(bandForDistance(5000)?.key, '5k');
      expect(bandForDistance(10000)?.key, '10k');
      expect(bandForDistance(21097)?.key, 'half'); // half marathon
      expect(bandForDistance(42195)?.key, 'marathon'); // marathon
      expect(bandForDistance(50000)?.key, 'ultra');
      expect(bandForDistance(160934)?.key, 'ultra'); // 100 miles
    });

    test('tolerates real-world wobble around the nominal', () {
      expect(bandForDistance(4200)?.key, '5k');
      expect(bandForDistance(5900)?.key, '5k');
      expect(bandForDistance(11500)?.key, '10k');
    });

    test('returns null in the gaps between race distances', () {
      expect(bandForDistance(3000), isNull); // below 5k floor
      expect(bandForDistance(7000), isNull); // between 5k and 10k
      expect(bandForDistance(15000), isNull); // between 10k and half
      expect(bandForDistance(30000), isNull); // between half and marathon
    });

    test('band edges are half-open [min, max)', () {
      expect(bandForDistance(6000), isNull); // exclusive 5k upper edge
      expect(bandForDistance(44499)?.key, 'marathon');
      expect(bandForDistance(44500)?.key, 'ultra');
    });
  });

  group('bandsToRanges', () {
    test('returns nulls when nothing is selected', () {
      final r = bandsToRanges([]);
      expect(r.min, isNull);
      expect(r.max, isNull);
    });

    test('builds parallel arrays for a single band', () {
      final r = bandsToRanges(['5k']);
      expect(r.min, [4000]);
      expect(r.max, [6000]);
    });

    test('carries an open-ended upper bound for ultra', () {
      final r = bandsToRanges(['ultra']);
      expect(r.min, [44500]);
      expect(r.max, [null]);
    });

    test('output order follows distanceBands, not input order', () {
      final r = bandsToRanges(['ultra', '5k', 'half']);
      expect(r.min, [4000, 19000, 44500]);
      expect(r.max, [6000, 23000, null]);
    });

    test('every band key round-trips', () {
      final keys = distanceBands.map((b) => b.key).toList();
      final r = bandsToRanges(keys);
      expect(r.min?.length, distanceBands.length);
      expect(r.max?.length, distanceBands.length);
    });
  });
}
