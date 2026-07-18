import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/races_screen.dart';

class _FakeRaceService extends RaceService {
  final List<RaceListingView> results;
  final bool runSignUpAvailable;
  bool importCalled = false;
  String? lastImportProvider;
  String? lastImportBib;

  _FakeRaceService({this.results = const [], this.runSignUpAvailable = false});

  @override
  Future<ImportRaceResultOutcome> importRaceResult({
    required String provider,
    required String listingId,
    String? bib,
    String? matchRunId,
    PastedRaceResult? result,
  }) async {
    importCalled = true;
    lastImportProvider = provider;
    lastImportBib = bib;
    return const ImportRaceResultOutcome(imported: 1, skipped: 0, enriched: 0);
  }

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

RaceListingView _listing(String id, String name,
        {int? distanceM, bool verified = true, String provider = 'manual'}) =>
    RaceListingView(
      id: id,
      provider: provider,
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

  testWidgets(
      'a runsignup listing offers the pull-import button when RunSignUp is configured',
      (tester) async {
    final service = _FakeRaceService(
      results: [_listing('r3', 'RSU Race', provider: 'runsignup')],
      runSignUpAvailable: true,
    );
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import my result'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Import my result'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining("RunSignUp import isn't available yet"),
      findsNothing,
    );
  });

  testWidgets(
      'the RunSignUp import is gated on a bib and passes it through (issue #360)',
      (tester) async {
    final service = _FakeRaceService(
      results: [_listing('r3b', 'RSU Race', provider: 'runsignup')],
      runSignUpAvailable: true,
    );
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import my result'));
    await tester.pumpAndSettle();

    final importButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Import my result'),
    );
    // Disabled until a bib is entered — an unscoped pull is refused client-side.
    expect(tester.widget<FilledButton>(importButton).onPressed, isNull);

    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
      '1234',
    );
    await tester.pump();

    expect(tester.widget<FilledButton>(importButton).onPressed, isNotNull);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(service.importCalled, isTrue);
    expect(service.lastImportProvider, 'runsignup');
    expect(service.lastImportBib, '1234');

    // Drain the success top-banner's pending timer (mobile-test gotcha).
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'a runsignup listing shows the unavailable note when RunSignUp is not configured',
      (tester) async {
    final service = _FakeRaceService(
      results: [_listing('r4', 'RSU Race', provider: 'runsignup')],
    );
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import my result'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Import my result'),
      ),
      findsNothing,
    );
    expect(
      find.textContaining("RunSignUp import isn't available yet"),
      findsOneWidget,
    );
  });

  testWidgets(
      'tapping Register with no handler app for the URL surfaces a banner instead of doing nothing',
      (tester) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    var launchCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, (call) async {
      // canLaunch reports no handler is registered for the URL; a real
      // launch call would be a bug in _launch since it should short-circuit.
      if (call.method == 'canLaunch') return false;
      if (call.method == 'launch' || call.method == 'launchUrl') {
        launchCalls++;
        return false;
      }
      return null;
    });
    addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, null));

    final service = _FakeRaceService(
      results: [_listing('r5', 'Broken Link 10k')],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Register'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't open that link."), findsOneWidget);
    expect(launchCalls, 0);

    // showTopBanner leaves a pending auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tapping Register with a malformed URL surfaces a banner rather than throwing',
      (tester) async {
    final service = _FakeRaceService(
      results: [
        RaceListingView(
          id: 'r6',
          provider: 'manual',
          providerRaceId: null,
          name: 'Malformed URL 5k',
          raceDate: '2027-09-12',
          distanceM: null,
          locationLabel: null,
          entryUrl: '::not a valid uri::',
          resultsUrl: null,
          isVerified: true,
          distanceMAway: null,
        ),
      ],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Register'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't open that link."), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });
}
