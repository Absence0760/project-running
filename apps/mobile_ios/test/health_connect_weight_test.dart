import 'package:flutter_test/flutter_test.dart';

import '../lib/column_limits.dart';
import '../lib/health_connect_importer.dart';

void main() {
  const key = 'body_metrics.weight_kg';

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

    test('the accepted range is the registered column bound, both ends', () {
      // The importer used to carry its own 30–300 kg, which is narrower than
      // the body-metrics field at the floor and WIDER at the ceiling — so an
      // import could seed a weight the field then refused to re-save, and a
      // light runner's real sample was dropped as noise. Written against the
      // registry so the two can no longer drift apart (decisions § 819).
      final min = columnMin(key).toDouble();
      final max = columnMax(key).toDouble();
      for (final kg in [min, max, (min + max) / 2]) {
        expect(
          HealthConnectImporter.selectLatestWeightKg([
            (kg: kg, at: DateTime(2026, 1, 1)),
          ]),
          kg,
          reason: '$kg is inside the column bound and must be accepted',
        );
      }
      for (final kg in [min - 0.01, max + 0.01]) {
        expect(
          HealthConnectImporter.selectLatestWeightKg([
            (kg: kg, at: DateTime(2026, 1, 1)),
          ]),
          isNull,
          reason: '$kg is outside the column bound and must be refused',
        );
      }
    });
  });
}
