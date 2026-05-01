import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/widgets/live_run_map.dart';

void main() {
  group('smoothTrack', () {
    test('returns input unchanged when fewer than 5 points', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 0.001),
        LatLng(0, 0.002),
        LatLng(0, 0.003),
      ];

      final out = smoothTrack(pts);

      expect(out.length, 4);
      for (int i = 0; i < pts.length; i++) {
        expect(out[i].latitude, pts[i].latitude);
        expect(out[i].longitude, pts[i].longitude);
      }
    });

    test('preserves first two and last two points unchanged', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 1),
        LatLng(0, 2),
        LatLng(0, 3),
        LatLng(0, 4),
      ];

      final out = smoothTrack(pts);

      expect(out[0].longitude, 0);
      expect(out[1].longitude, 1);
      expect(out[3].longitude, 3);
      expect(out[4].longitude, 4);
    });

    test('weighted average for interior point: (a+2b+3c+2d+e)/9', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 1),
        LatLng(0, 2),
        LatLng(0, 3),
        LatLng(0, 4),
      ];

      final out = smoothTrack(pts);

      expect(out[2].longitude, closeTo((0 + 2 * 1 + 3 * 2 + 2 * 3 + 4) / 9, 1e-12));
      expect(out[2].latitude, 0);
    });

    test('co-linear evenly-spaced points are unchanged by the filter', () {
      final pts = List.generate(11, (i) => LatLng(0, i.toDouble()));

      final out = smoothTrack(pts);

      for (int i = 0; i < pts.length; i++) {
        expect(out[i].longitude, closeTo(pts[i].longitude, 1e-12));
        expect(out[i].latitude, 0);
      }
    });

    test('zig-zag jitter is attenuated toward the local mean', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 1),
        LatLng(1, 2),
        LatLng(0, 3),
        LatLng(0, 4),
      ];

      final out = smoothTrack(pts);

      expect(out[2].latitude, closeTo(3 / 9, 1e-12));
      expect(out[2].longitude, closeTo(2, 1e-12));
    });

    test('returns a new list — does not mutate input', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 1),
        LatLng(1, 2),
        LatLng(0, 3),
        LatLng(0, 4),
      ];
      final originalCenterLat = pts[2].latitude;

      final out = smoothTrack(pts);

      expect(identical(out, pts), isFalse);
      expect(pts[2].latitude, originalCenterLat);
      expect(out[2].latitude, isNot(originalCenterLat));
    });

    test('length-1 and length-0 inputs handled without error', () {
      expect(smoothTrack(<LatLng>[]).length, 0);
      expect(smoothTrack([LatLng(1, 2)]).length, 1);
      expect(smoothTrack([LatLng(1, 2)])[0].longitude, 2);
    });

    test('length-5 input smooths exactly index 2', () {
      final pts = [
        LatLng(0, 0),
        LatLng(0, 0),
        LatLng(0, 9),
        LatLng(0, 0),
        LatLng(0, 0),
      ];

      final out = smoothTrack(pts);

      expect(out[0].longitude, 0);
      expect(out[1].longitude, 0);
      expect(out[2].longitude, closeTo(3, 1e-12));
      expect(out[3].longitude, 0);
      expect(out[4].longitude, 0);
    });

    test('weights sum to 9 — applying to a constant value returns that value', () {
      final pts = List.generate(7, (_) => LatLng(47.37, 8.54));

      final out = smoothTrack(pts);

      for (final p in out) {
        expect(p.latitude, closeTo(47.37, 1e-12));
        expect(p.longitude, closeTo(8.54, 1e-12));
      }
    });
  });
}
