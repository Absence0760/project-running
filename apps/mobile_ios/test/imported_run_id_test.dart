import 'package:flutter_test/flutter_test.dart';

import '../lib/imported_run_id.dart';

void main() {
  group('stableRunIdFromExternalId', () {
    test('is deterministic for the same external_id', () {
      final a = stableRunIdFromExternalId('strava:98765');
      final b = stableRunIdFromExternalId('strava:98765');
      expect(a, b);
    });

    test('differs for different external_ids', () {
      final a = stableRunIdFromExternalId('strava:98765');
      final b = stableRunIdFromExternalId('strava:98766');
      expect(a, isNot(b));
    });

    test('differs across source namespaces even for the same suffix', () {
      final strava = stableRunIdFromExternalId('strava:123');
      final hc = stableRunIdFromExternalId('healthconnect:123');
      expect(strava, isNot(hc));
    });

    test('produces a canonical v5 UUID', () {
      final id = stableRunIdFromExternalId('healthconnect:abc-123');
      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });
}
