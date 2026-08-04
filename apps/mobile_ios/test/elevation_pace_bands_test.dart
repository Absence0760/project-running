// Issue #666 round 2: the run-detail elevation chart banded its fill by
// pace using the semantic success / warning / danger tokens at 0.25-0.35
// alpha. Composited over the page background that landed at 1.03:1 (light)
// and 1.10:1 (dark) between the faster and slower bands — a distinction
// carried entirely by hue, out of reach for red-green colour-vision
// deficiency and invisible in greyscale. These floors pin the replacement.
//
// A WCAG contrast ratio is a function of relative luminance alone, so a
// ratio floor IS a greyscale-separation floor; the monotonic-luminance test
// pins the ordering that the ratios on their own would not.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/screens/run_detail_screen.dart' show elevationPaceBandColours;

/// Neighbouring bands must be this far apart.
const _adjacentFloor = 2.0;

/// Faster vs slower — the pair the encoding exists to distinguish.
const _extremeFloor = 4.0;

/// Every band against the page it is painted on.
const _backgroundFloor = 1.5;

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  return 0.2126 * chan(c.red.toDouble()) +
      // ignore: deprecated_member_use
      0.7152 * chan(c.green.toDouble()) +
      // ignore: deprecated_member_use
      0.0722 * chan(c.blue.toDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
    final name = theme.brightness.name;
    final bg = theme.scaffoldBackgroundColor;
    final bands = elevationPaceBandColours(theme.brightness);

    group('elevation pace bands ($name)', () {
      test('three distinct fills', () {
        expect(bands, hasLength(3));
        expect(bands.toSet(), hasLength(3));
      });

      test('neighbouring bands clear $_adjacentFloor:1', () {
        expect(_contrast(bands[0], bands[1]),
            greaterThanOrEqualTo(_adjacentFloor));
        expect(_contrast(bands[1], bands[2]),
            greaterThanOrEqualTo(_adjacentFloor));
      });

      test('faster vs slower clears $_extremeFloor:1', () {
        expect(
            _contrast(bands[0], bands[2]), greaterThanOrEqualTo(_extremeFloor));
      });

      test('every band clears $_backgroundFloor:1 against the page', () {
        for (final band in bands) {
          expect(_contrast(band, bg), greaterThanOrEqualTo(_backgroundFloor));
        }
      });

      test('luminance is strictly monotonic, so the ramp survives greyscale',
          () {
        final l = bands.map(_luminance).toList();
        final ascending = l[0] < l[1] && l[1] < l[2];
        final descending = l[0] > l[1] && l[1] > l[2];
        expect(ascending || descending, isTrue,
            reason: 'a tie or a fold in the luminance ramp collapses two '
                'bands into one shade for a greyscale reader');
      });

      test('slower sits furthest from the page background', () {
        expect(_contrast(bands[2], bg), greaterThan(_contrast(bands[0], bg)),
            reason: 'heavier ink means slower in both themes');
      });
    });
  }
}
