import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/run_detail_screen.dart';

void main() {
  final rawTrack = <Waypoint>[
    const Waypoint(lat: 1, lng: 1),
    const Waypoint(lat: 2, lng: 2),
    const Waypoint(lat: 3, lng: 3),
  ];
  final matchedTrack = <Waypoint>[
    const Waypoint(lat: 10, lng: 10),
    const Waypoint(lat: 11, lng: 11),
  ];
  final matched = RunMatchInfo(status: MatchStatus.matched, track: matchedTrack);

  group('displayedRunTrack', () {
    test('prefers matched line when present and showRaw is off (default)', () {
      final shown = displayedRunTrack(rawTrack, matched, showRaw: false);
      expect(identical(shown, matchedTrack), isTrue);
    });

    test('showRaw forces the raw track even when a matched line exists', () {
      final shown = displayedRunTrack(rawTrack, matched, showRaw: true);
      expect(identical(shown, rawTrack), isTrue);
    });

    test('falls back to raw when there is no match info', () {
      expect(
        identical(displayedRunTrack(rawTrack, null, showRaw: false), rawTrack),
        isTrue,
      );
      expect(
        identical(displayedRunTrack(rawTrack, null, showRaw: true), rawTrack),
        isTrue,
      );
    });

    test('falls back to raw when match is not renderable', () {
      const pending = RunMatchInfo(status: MatchStatus.pending);
      const tooShort = RunMatchInfo(
        status: MatchStatus.matched,
        track: [Waypoint(lat: 0, lng: 0)],
      );
      expect(
        identical(displayedRunTrack(rawTrack, pending, showRaw: false),
            rawTrack),
        isTrue,
      );
      expect(
        identical(displayedRunTrack(rawTrack, tooShort, showRaw: false),
            rawTrack),
        isTrue,
      );
    });
  });
}
