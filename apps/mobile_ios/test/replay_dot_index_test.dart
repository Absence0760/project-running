import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/run_detail_screen.dart';

void main() {
  group('replayDotIndex', () {
    test('null replay index → null (replay not running)', () {
      expect(replayDotIndex(null, 50, 50), isNull);
    });

    test('degenerate tracks → null', () {
      expect(replayDotIndex(0, 1, 10), isNull); // raw too short
      expect(replayDotIndex(0, 10, 0), isNull); // displayed empty
    });

    test('same-length track (no map match) round-trips to the same index', () {
      // The displayed line IS run.track — the dot must keep its exact
      // index so it snaps onto the same vertex it always did.
      expect(replayDotIndex(0, 81, 81), 0);
      expect(replayDotIndex(40, 81, 81), 40);
      expect(replayDotIndex(80, 81, 81), 80);
    });

    test('shorter matched track maps proportionally and stays in range', () {
      // raw 21 points, matched line 11 points: the dot must track the
      // matched line, not index past its end.
      expect(replayDotIndex(0, 21, 11), 0); // start
      expect(replayDotIndex(10, 21, 11), 5); // halfway
      expect(replayDotIndex(20, 21, 11), 10); // end (would be out of range raw)
    });

    test('longer matched track maps proportionally', () {
      expect(replayDotIndex(0, 11, 21), 0);
      expect(replayDotIndex(5, 11, 21), 10); // halfway
      expect(replayDotIndex(10, 11, 21), 20); // end
    });

    test('result is always a valid index into the displayed track', () {
      for (var i = 0; i < 21; i++) {
        final idx = replayDotIndex(i, 21, 7)!;
        expect(idx, inInclusiveRange(0, 6));
      }
    });
  });
}
