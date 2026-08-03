// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/geo.dart';

/// Mirror of `apps/web/src/lib/routes/geo.test.ts`, itself mirroring the
/// firmware's `watch_core::geo` tests (decisions §463). Keep all three in
/// lockstep — every planar frame on both platforms takes its longitude
/// deltas through here.

void main() {
  test('a delta within a hemisphere is the plain subtraction, bit for bit', () {
    const pairs = [
      [-105.2705, -105.269445],
      [51.5, 51.51],
      [0.0, 0.0],
      [-179.0, 179.0 - 360],
      [12.34567, -98.7654321],
    ];
    for (final p in pairs) {
      expect(lonDeltaDeg(p[0], p[1]), p[1] - p[0], reason: '${p[0]} -> ${p[1]}');
    }
  });

  test('a delta across the antimeridian takes the short way', () {
    expect((lonDeltaDeg(179.99, -179.97) - 0.04).abs() < 1e-9, isTrue);
    expect((lonDeltaDeg(-179.97, 179.99) + 0.04).abs() < 1e-9, isTrue);
    expect((lonDeltaDeg(179.9, -179.9) - 0.2).abs() < 1e-9, isTrue);
    // The plain subtraction is wrong by a whole turn, which is the bug.
    expect((-179.97 - 179.99 + 359.96).abs() < 1e-9, isTrue);
  });

  test('opposite meridians resolve consistently rather than flapping', () {
    expect(lonDeltaDeg(0, 180), -180.0);
    expect(lonDeltaDeg(0, -180), -180.0);
    expect(wrapLonDeg(wrapLonDeg(180)), wrapLonDeg(180));
    expect(wrapLonDeg(-180), -180.0);
  });

  test('unwrapping leaves a longitude already near the reference untouched',
      () {
    const pairs = [
      [-105.27, -105.26],
      [0.0, 179.9],
      [0.0, -179.9],
      [60.0, 60.0],
    ];
    for (final p in pairs) {
      expect(unwrapLonDeg(p[0], p[1]), p[1], reason: '${p[0]} ${p[1]}');
    }
  });

  test('unwrapping carries a course past the line instead of jumping it', () {
    // A course anchored at 179.98 whose far end is at -179.96: the box
    // spans 0.06°, not 359.94.
    const a = 179.98;
    final b = unwrapLonDeg(a, -179.96);
    expect((b - 180.04).abs() < 1e-9, isTrue, reason: 'unwrapped to $b');
    expect((b - a - 0.06).abs() < 1e-9, isTrue);
    expect((wrapLonDeg(b) - -179.96).abs() < 1e-9, isTrue);
  });

  test('a non-finite longitude stays non-finite rather than becoming a number',
      () {
    expect(lonDeltaDeg(double.nan, 0).isNaN, isTrue);
    expect(lonDeltaDeg(0, double.nan).isNaN, isTrue);
    expect(wrapLonDeg(double.infinity).isFinite, isFalse);
    expect(unwrapLonDeg(0, double.infinity).isFinite, isFalse);
  });
}
