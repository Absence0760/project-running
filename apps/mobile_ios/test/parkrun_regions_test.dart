import 'package:flutter_test/flutter_test.dart';

import '../lib/parkrun_regions.dart';

void main() {
  group('parkrunLikelyUnavailable', () {
    test('parkrun regions show no hint', () {
      expect(parkrunLikelyUnavailable('en-US'), isFalse);
      expect(parkrunLikelyUnavailable('en-GB'), isFalse);
      expect(parkrunLikelyUnavailable('de-DE'), isFalse);
      expect(parkrunLikelyUnavailable('ja-JP'), isFalse);
      expect(parkrunLikelyUnavailable('en-AU'), isFalse);
      expect(parkrunLikelyUnavailable('af-ZA'), isFalse);
    });

    test('regions outside the parkrun footprint show the hint', () {
      expect(parkrunLikelyUnavailable('es-ES'), isTrue);
      expect(parkrunLikelyUnavailable('fr-FR'), isTrue);
      expect(parkrunLikelyUnavailable('pt-BR'), isTrue);
      expect(parkrunLikelyUnavailable('id-ID'), isTrue);
      expect(parkrunLikelyUnavailable('zh-Hant-TW'), isTrue);
    });

    test('accepts POSIX underscore tags', () {
      expect(parkrunLikelyUnavailable('en_GB'), isFalse);
      expect(parkrunLikelyUnavailable('es_ES'), isTrue);
    });

    test('an unknown or region-less locale shows no hint (no false warning)', () {
      expect(parkrunLikelyUnavailable('en'), isFalse);
      expect(parkrunLikelyUnavailable(''), isFalse);
      expect(parkrunLikelyUnavailable('not-a-locale!!'), isFalse);
    });

    test('region codes are two-letter uppercase', () {
      for (final r in parkrunRegions) {
        expect(RegExp(r'^[A-Z]{2}$').hasMatch(r), isTrue, reason: r);
      }
    });
  });
}
