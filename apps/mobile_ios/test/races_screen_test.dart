import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/race_service.dart';
import '../lib/training.dart' show toIsoDate;
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
        {int? distanceM,
        double? distanceMAway,
        bool verified = true,
        String provider = 'manual',
        String raceDate = '2027-09-12'}) =>
    RaceListingView(
      id: id,
      provider: provider,
      providerRaceId: null,
      name: name,
      raceDate: raceDate,
      distanceM: distanceM,
      locationLabel: 'Richmond, VA',
      entryUrl: 'https://example.com/register',
      resultsUrl: null,
      isVerified: verified,
      distanceMAway: distanceMAway,
    );

/// A race date [days] out from today. The plan action is gated on a live
/// `racePlanPreset` call, so a fixture pinned to a calendar date would stop
/// exercising the gate the day it fell into the past.
String _isoDaysOut(int days) =>
    toIsoDate(DateTime.now().add(Duration(days: days)));

Widget _app(RaceService service,
        {double textScale = 1.0, double bottomInset = 0}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
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

  testWidgets(
      'the distance-band chip rail takes its height from the chips, not a '
      'literal 40 px lane (issue #666 V12)', (tester) async {
    final service = _FakeRaceService(results: const []);

    await tester.pumpWidget(_app(service));
    await tester.pump();
    final chip = find.byType(ChoiceChip).first;
    final small = tester.getSize(chip).height;
    // A Material chip's own tap target is 48; the old 40 px lane squeezed it.
    expect(small, greaterThanOrEqualTo(48));

    await tester.pumpWidget(_app(service, textScale: 2.0));
    await tester.pump();
    // Pre-fix the chip measured exactly 40.0 here while needing 58, so its
    // label was cropped inside the rail.
    expect(tester.getSize(chip).height, greaterThan(small));
  });

  // Issue #666 C5: the list reserved nothing at all for the Submit-race FAB,
  // so the last card sat under it — worst on a 3-button nav bar, which lifts
  // the button another ~48dp into the list.
  testWidgets('the last race card clears the FAB, nav bar included',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeRaceService(results: [
      for (var i = 0; i < 8; i++) _listing('r$i', 'Race $i', distanceM: 10000),
    ]);
    await tester.pumpWidget(_app(service, bottomInset: 48));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Race 7'), 300,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();

    final lastCard = find.ancestor(
        of: find.text('Race 7'), matching: find.byType(Card));
    expect(
      tester.getRect(lastCard).bottom,
      lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
      reason: 'the last card must end above the button that floats over it',
    );
  });

  group('RacesScreen — the runner\'s distance unit', () {
    testWidgets('a mile-unit runner reads the card in miles', (tester) async {
      // Both figures on a race card were built by dividing metres by 1000 and
      // writing " km" after it, so browsing races was the one surface that
      // ignored the unit pref the rest of the app honours.
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      final service = _FakeRaceService(results: [
        _listing('r-mi', 'Imperial Half',
            distanceM: 21097, distanceMAway: 8046.72),
      ]);
      await tester.pumpWidget(_app(service));
      await tester.pump();

      expect(find.textContaining('13.11 mi'), findsOneWidget,
          reason: 'the race distance');
      expect(find.textContaining('5.00 mi away'), findsOneWidget,
          reason: 'the distance-from-you label');
      expect(find.textContaining(' km'), findsNothing);
    });

    testWidgets('a km-unit runner still reads kilometres', (tester) async {
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      final service = _FakeRaceService(results: [
        _listing('r-km', 'Metric Half', distanceM: 21097, distanceMAway: 5000),
      ]);
      await tester.pumpWidget(_app(service));
      await tester.pump();

      expect(find.textContaining('21.10 km'), findsOneWidget);
      expect(find.textContaining('5.00 km away'), findsOneWidget);
    });
  });

  testWidgets('a race far enough out offers to build a plan for it',
      (tester) async {
    final service = _FakeRaceService(
      results: [
        _listing('r7', 'Next Autumn Half',
            distanceM: 21097,
            raceDate: _isoDaysOut(220)),
      ],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.text('Train for this race'), findsOneWidget);
  });

  testWidgets('a race already run offers no plan action rather than a refusal',
      (tester) async {
    final service = _FakeRaceService(
      results: [
        _listing('r8', 'Last Month 10K',
            distanceM: 10000, raceDate: _isoDaysOut(-30)),
      ],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.text('Last Month 10K'), findsOneWidget);
    expect(find.text('Train for this race'), findsNothing);
  });

  testWidgets('a race too close to plan for offers no plan action',
      (tester) async {
    final service = _FakeRaceService(
      results: [
        _listing('r9', 'Parkrun Saturday',
            distanceM: 5000, raceDate: _isoDaysOut(9)),
      ],
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.text('Train for this race'), findsNothing);
  });
}

