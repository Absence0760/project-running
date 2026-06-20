import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/races_screen.dart';

class _FakeRaceService extends RaceService {
  final List<RaceListingView> results;
  final bool runSignUpAvailable;

  _FakeRaceService({this.results = const [], this.runSignUpAvailable = false});

  @override
  Future<List<RaceListingView>> searchRaceListings({
    String? query,
    String? distance,
    String? from,
    String? to,
    String? nearPlace,
    String? mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
    int limit = 60,
  }) async {
    if (distance == '5k') return const [];
    if (query != null && query.isNotEmpty) {
      return results.where((r) => r.name.contains(query)).toList();
    }
    return results;
  }

  @override
  Future<bool> isRunSignUpConfigured() async => runSignUpAvailable;
}

RaceListingView _listing(String id, String name, {int? distanceM, bool verified = true}) =>
    RaceListingView(
      id: id,
      provider: 'manual',
      providerRaceId: null,
      name: name,
      raceDate: '2027-09-12',
      distanceM: distanceM,
      locationLabel: 'Richmond, VA',
      entryUrl: 'https://example.com/register',
      resultsUrl: null,
      isVerified: verified,
      distanceMAway: null,
    );

Widget _app(RaceService service) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RacesScreen(service: service),
    );

void main() {
  testWidgets('renders the empty state when no listings match', (tester) async {
    await tester.pumpWidget(_app(_FakeRaceService(results: const [])));
    await tester.pump();
    expect(find.text('No races match these filters yet.'), findsOneWidget);
  });

  testWidgets('renders a listing card with name, register, and import', (tester) async {
    final service = _FakeRaceService(
      results: [_listing('r1', 'E2E Half', distanceM: 21097)],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.text('E2E Half'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Import my result'), findsOneWidget);
  });

  testWidgets('an unverified listing shows the unverified badge', (tester) async {
    final service = _FakeRaceService(
      results: [_listing('r2', 'Crowd Race', verified: false)],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.text('Unverified'), findsOneWidget);
  });
}
