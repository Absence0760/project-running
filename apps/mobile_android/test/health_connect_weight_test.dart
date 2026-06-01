import 'package:flutter_test/flutter_test.dart';

import '../lib/health_connect_importer.dart';

void main() {
  group('HealthConnectImporter.selectLatestWeightKg', () {
    test('picks the most-recent in-range sample', () {
      final kg = HealthConnectImporter.selectLatestWeightKg([
        (kg: 70, at: DateTime(2026, 1, 1)),
        (kg: 72, at: DateTime(2026, 5, 1)),
        (kg: 71, at: DateTime(2026, 3, 1)),
      ]);
      expect(kg, 72);
    });

    test('ignores out-of-range samples (stray / unit-confused)', () {
      final kg = HealthConnectImporter.selectLatestWeightKg([
        (kg: 72, at: DateTime(2026, 1, 1)),
        (kg: 700, at: DateTime(2026, 6, 1)), // grams mistaken for kg
        (kg: 5, at: DateTime(2026, 6, 2)), // implausible
      ]);
      expect(kg, 72);
    });

    test('returns null when no sample qualifies', () {
      expect(HealthConnectImporter.selectLatestWeightKg([]), isNull);
      expect(
        HealthConnectImporter.selectLatestWeightKg([
          (kg: 10, at: DateTime(2026, 1, 1)),
          (kg: 400, at: DateTime(2026, 1, 2)),
        ]),
        isNull,
      );
    });
  });
}
