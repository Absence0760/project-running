import 'package:flutter_test/flutter_test.dart';
import '../lib/privacy.dart';

const _home = PrivacyZone(lat: 40.7128, lng: -74.006, radiusM: 200);

class _Pt {
  final double lat;
  final double lng;
  const _Pt(this.lat, this.lng);
}

double _lat(_Pt p) => p.lat;
double _lng(_Pt p) => p.lng;

/// Tiny offset that crosses outside a 200 m radius — about 350 m east.
_Pt _offset(double lat, double lng, double dLng) => _Pt(lat, lng + dLng);

void main() {
  group('isInAnyZone', () {
    test('empty zones returns false', () {
      expect(isInAnyZone(0, 0, const []), isFalse);
    });

    test('center is in zone', () {
      expect(isInAnyZone(_home.lat, _home.lng, const [_home]), isTrue);
    });

    test('far point is not', () {
      final p = _offset(_home.lat, _home.lng, 0.01);
      expect(isInAnyZone(p.lat, p.lng, const [_home]), isFalse);
    });
  });

  group('clipPointsToZones', () {
    test('empty zones returns input', () {
      final pts = const [_Pt(1, 1), _Pt(2, 2)];
      final out = clipPointsToZones<_Pt>(pts, const [],
          latOf: _lat, lngOf: _lng);
      expect(out, equals(pts));
    });

    test('drops leading + trailing in-zone', () {
      final pts = [
        _Pt(_home.lat, _home.lng), // in
        _Pt(_home.lat, _home.lng), // in
        _offset(_home.lat, _home.lng, 0.01), // out (mid)
        _offset(_home.lat, _home.lng, 0.02), // out (mid)
        _Pt(_home.lat, _home.lng), // in (trailing)
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng);
      expect(out.length, 2);
      expect(identical(out[0], pts[2]), isTrue);
      expect(identical(out[1], pts[3]), isTrue);
    });

    test('keeps interior in-zone segments (only ends are clipped)', () {
      final pts = [
        _offset(_home.lat, _home.lng, 0.01), // out
        _Pt(_home.lat, _home.lng), // in (interior — kept)
        _offset(_home.lat, _home.lng, 0.02), // out
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng);
      expect(out, equals(pts));
    });

    test('every point in zone returns empty', () {
      final pts = [
        _Pt(_home.lat, _home.lng),
        _Pt(_home.lat + 0.0001, _home.lng + 0.0001),
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng);
      expect(out, isEmpty);
    });

    test('multiple zones — clips against the union', () {
      const work = PrivacyZone(lat: 40.75, lng: -73.99, radiusM: 200);
      final pts = [
        _Pt(_home.lat, _home.lng), // in home
        _offset(_home.lat, _home.lng, 0.01), // out (mid)
        _Pt(work.lat, work.lng), // in work (trailing)
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home, work],
          latOf: _lat, lngOf: _lng);
      expect(out.length, 1);
      expect(identical(out[0], pts[1]), isTrue);
    });
  });
}
