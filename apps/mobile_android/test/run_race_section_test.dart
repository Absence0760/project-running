import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/widgets/run_race_section.dart';

class _FakeRaceService extends RaceService {
  final RaceResultForRun? result;
  final List<RaceListingView> candidates;

  _FakeRaceService({this.result, this.candidates = const []});

  @override
  Future<RaceResultForRun?> fetchRaceResultForRun(String runId) async => result;

  @override
  Future<List<RaceListingView>> findRaceMatchCandidates(String runId) async =>
      candidates;

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
  }) async =>
      candidates;

  @override
  Future<bool> isRunSignUpConfigured() async => false;
}

RaceListingView _listing(String id, String name, {int? distanceM}) =>
    RaceListingView(
      id: id,
      provider: 'manual',
      providerRaceId: null,
      name: name,
      raceDate: '2027-04-18',
      distanceM: distanceM,
      locationLabel: null,
      entryUrl: null,
      resultsUrl: null,
      isVerified: true,
      distanceMAway: null,
    );

Widget _app(RaceService service, {required String startedAt, double? distanceM}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunRaceSection(
          service: service,
          runId: 'run-1',
          startedAt: startedAt,
          distanceM: distanceM,
        ),
      ),
    );

void main() {
  testWidgets('renders the official result when the run carries one',
      (tester) async {
    final service = _FakeRaceService(
      result: const RaceResultForRun(
        listing: null,
        raceName: 'Boston Marathon',
        bib: '128',
        chipTime: '3:21:45',
        gunTime: null,
        overallPlace: 128,
        ageGroupPlace: null,
        ageGroup: null,
      ),
    );
    await tester.pumpWidget(
        _app(service, startedAt: '2027-04-18T13:00:00.000Z', distanceM: 42100));
    await tester.pumpAndSettle();
    expect(find.text('Official result'), findsOneWidget);
    expect(find.text('Boston Marathon'), findsOneWidget);
    expect(find.text('3:21:45'), findsOneWidget);
  });

  testWidgets('offers the auto-match prompt for a same-day, same-band listing',
      (tester) async {
    final service = _FakeRaceService(
      candidates: [_listing('l1', 'Boston Marathon', distanceM: 42195)],
    );
    await tester.pumpWidget(
        _app(service, startedAt: '2027-04-18T13:00:00.000Z', distanceM: 42100));
    await tester.pumpAndSettle();
    expect(find.textContaining('Boston Marathon'), findsOneWidget);
    expect(find.text('Import result'), findsOneWidget);
    expect(find.text('Not this race'), findsOneWidget);
  });

  testWidgets('dismissing the prompt hides it', (tester) async {
    final service = _FakeRaceService(
      candidates: [_listing('l1', 'Boston Marathon', distanceM: 42195)],
    );
    await tester.pumpWidget(
        _app(service, startedAt: '2027-04-18T13:00:00.000Z', distanceM: 42100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not this race'));
    await tester.pumpAndSettle();
    expect(find.text('Import result'), findsNothing);
  });

  testWidgets('renders nothing when there is no result and no candidate',
      (tester) async {
    final service = _FakeRaceService();
    await tester.pumpWidget(
        _app(service, startedAt: '2027-04-18T13:00:00.000Z', distanceM: 42100));
    await tester.pumpAndSettle();
    expect(find.text('Official result'), findsNothing);
    expect(find.text('Import result'), findsNothing);
  });
}
