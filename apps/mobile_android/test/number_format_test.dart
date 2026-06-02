import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/number_format.dart';
import '../lib/l10n/locale_support.dart';
import '../lib/preferences.dart';

void main() {
  tearDown(() => registerActiveLocaleTag('en'));

  group('formatFixed', () {
    test('en matches the old toStringAsFixed exactly', () {
      expect(formatFixed(5.214, 2, 'en'), '5.21');
      expect(formatFixed(5.214, 2, 'en'), 5.214.toStringAsFixed(2));
      expect(formatFixed(12.34, 1, 'en'), '12.3');
      expect(formatFixed(0, 2, 'en'), '0.00');
    });

    test('en does NOT group thousands (preserves old elevation output)', () {
      // 10000 m elevation must render "10000", not "10,000".
      expect(formatFixed(10000, 0, 'en'), '10000');
      expect(formatFixed(10000, 0, 'en'), 10000.0.round().toString());
      expect(formatFixed(1234.5, 2, 'en'), '1234.50');
    });

    test('de uses a comma decimal separator', () {
      expect(formatFixed(5.21, 2, 'de'), '5,21');
      expect(formatFixed(12.3, 1, 'de'), '12,3');
      expect(formatFixed(10000, 0, 'de'), '10000');
    });

    test('negatives keep the ASCII minus for the shipped locales', () {
      expect(formatFixed(-3.5, 1, 'en'), '-3.5');
      expect(formatFixed(-3.5, 1, 'de'), '-3,5');
    });
  });

  group('UnitFormat respects the active locale', () {
    test('distance renders en with a dot, de with a comma', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.distance(5210, DistanceUnit.km), '5.21 km');
      registerActiveLocaleTag('de');
      expect(UnitFormat.distance(5210, DistanceUnit.km), '5,21 km');
    });

    test('miles distance is locale-aware', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.distance(1609.344, DistanceUnit.mi), '1.00 mi');
      registerActiveLocaleTag('de');
      expect(UnitFormat.distance(1609.344, DistanceUnit.mi), '1,00 mi');
    });

    test('speed is locale-aware', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.speed(360, DistanceUnit.km), '10.0');
      registerActiveLocaleTag('de');
      expect(UnitFormat.speed(360, DistanceUnit.km), '10,0');
    });

    test('elevation is locale-aware and ungrouped', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.elevation(120, DistanceUnit.km), '120 m');
      expect(UnitFormat.elevation(10000, DistanceUnit.km), '10000 m');
      registerActiveLocaleTag('de');
      expect(UnitFormat.elevation(120, DistanceUnit.km), '120 m');
    });
  });
}
