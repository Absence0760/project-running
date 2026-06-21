import 'package:flutter_test/flutter_test.dart';

import '../lib/race_service.dart';

// The wire-level probe (isChronoTrackConfigured) + importRaceResult dispatch
// need a live Supabase session, which mobile has no e2e for by design
// (docs/testing/testing.md). These pin the twin-shared, network-free contract:
// the distinct fail-closed exception type exists and a ChronoTrack pasted-result
// payload round-trips the same shape the EF consumes.
void main() {
  test('ChronoTrackUnavailable is a distinct fail-closed exception', () {
    expect(const ChronoTrackUnavailable(), isA<Exception>());
    expect(const ChronoTrackUnavailable(), isNot(isA<RunSignUpUnavailable>()));
  });

  test('PastedRaceResult serialises only the set fields', () {
    expect(const PastedRaceResult().toJson(), <String, dynamic>{});
    expect(
      const PastedRaceResult(bib: '77', chipTime: '0:55:10', overallPlace: 9).toJson(),
      {'bib': '77', 'chip_time': '0:55:10', 'overall_place': 9},
    );
  });
}
