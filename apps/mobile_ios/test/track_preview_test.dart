import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/track_preview.dart';

Waypoint _w(double lat, double lng) => Waypoint(lat: lat, lng: lng);

void main() {
  group('isTrackRenderable', () {
    test('rejects empty and single-point tracks', () {
      expect(isTrackRenderable(const []), isFalse);
      expect(isTrackRenderable([_w(0, 0)]), isFalse);
    });

    test('rejects tracks below the 5 m jitter threshold', () {
      // ~1 m diagonal — within GPS noise for a stationary device.
      expect(
        isTrackRenderable([_w(51.5074, -0.1278), _w(51.5074009, -0.1278009)]),
        isFalse,
      );
    });

    test('accepts a tiny but genuine lap (>5 m diagonal)', () {
      // ~14 m diagonal — small but real.
      expect(
        isTrackRenderable([_w(51.5074, -0.1278), _w(51.50749, -0.12780)]),
        isTrue,
      );
    });

    test('accepts a typical multi-km loop', () {
      expect(
        isTrackRenderable([
          _w(51.5074, -0.1278),
          _w(51.5174, -0.1378),
          _w(51.5274, -0.1278),
          _w(51.5174, -0.1178),
          _w(51.5074, -0.1278),
        ]),
        isTrue,
      );
    });
  });
}
