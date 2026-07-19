// Widget tests for DiscoverScreen — the Social hub's cross-club activity
// Discover tab. Mirrors apps/web/src/lib/components/SocialDiscover.svelte +
// the search_public_events RPC. The api is faked (override searchPublicEvents)
// so the result-rendering + filter-wiring paths run without a live stack.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/discover_screen.dart';
import '../lib/social_service.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this._rows);
  final List<PublicEventResult> _rows;
  Map<String, Object?> lastArgs = const {};

  @override
  Future<List<PublicEventResult>> searchPublicEvents({
    String? query,
    String? category,
    String? cadence,
    String? byday,
    String? paid,
    String? time,
    int limit = 60,
  }) async {
    lastArgs = {
      'query': query,
      'category': category,
      'cadence': cadence,
      'byday': byday,
      'paid': paid,
      'time': time,
    };
    return _rows;
  }
}

class _ThrowingApi extends ApiClient {
  // Throws until `failing` is flipped false, so a test can simulate recovery.
  bool failing = true;

  @override
  Future<List<PublicEventResult>> searchPublicEvents({
    String? query,
    String? category,
    String? cadence,
    String? byday,
    String? paid,
    String? time,
    int limit = 60,
  }) async {
    if (failing) throw Exception('simulated failure');
    return const [];
  }
}

PublicEventResult _ev({
  String id = 'ev1',
  String title = 'Sunday Long Run',
  String category = 'class',
  String? discipline = 'Reformer Pilates',
  String? freq = 'weekly',
  List<String>? byday = const ['MO'],
  int? priceCents = 1800,
  String? currency = 'usd',
}) =>
    PublicEventResult(
      id: id,
      clubId: 'club1',
      clubName: 'Norfolk Botanical Runners',
      clubSlug: 'norfolk-botanical-runners',
      title: title,
      category: category,
      discipline: discipline,
      startsAt: DateTime.utc(2026, 6, 15, 22, 0),
      timezone: 'America/New_York',
      durationMin: 50,
      recurrenceFreq: freq,
      recurrenceByday: byday,
      capacity: 6,
      priceCents: priceCents,
      currency: currency,
    );

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Future<void> _settle(WidgetTester tester) async {
  // The fake resolves immediately, but the loading state shows a
  // CircularProgressIndicator (an indefinite animation) so pumpAndSettle
  // would hang — pump twice to drain the microtask + one frame instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('renders a result card with discipline title, club, and price',
      (tester) async {
    final api = _FakeApi([_ev()]);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    // Discipline wins over title when present (web parity).
    expect(find.text('Reformer Pilates'), findsOneWidget);
    expect(find.text('Norfolk Botanical Runners'), findsOneWidget);
    // Priced event → a currency-formatted chip on the card. ($18.00).
    // (The price *filter* row also has a "Free" chip, so we can't assert
    // the absence of "Free" globally — the formatted amount is the proof.)
    expect(find.textContaining('18.00'), findsOneWidget);
  });

  testWidgets('long title + club name truncate with an ellipsis (no overflow)',
      (tester) async {
    final api = _FakeApi([
      _ev(
        discipline:
            'Extremely Long Reformer Pilates Mobility And Core Conditioning Class Name',
      ),
    ]);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    final title = tester.widget<Text>(find.text(
        'Extremely Long Reformer Pilates Mobility And Core Conditioning Class Name'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);

    final club =
        tester.widget<Text>(find.text('Norfolk Botanical Runners'));
    expect(club.maxLines, 1);
    expect(club.overflow, TextOverflow.ellipsis);
  });

  testWidgets('falls back to the title when discipline is null',
      (tester) async {
    final api = _FakeApi([
      _ev(discipline: null, title: 'Saturday Sunrise 5K', category: 'run'),
    ]);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(find.text('Saturday Sunrise 5K'), findsOneWidget);
  });

  testWidgets('a free event shows the Free price label', (tester) async {
    final api = _FakeApi([_ev(priceCents: null, currency: null)]);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    // The card's price chip + the price-filter "Free" chip → exactly two.
    expect(find.text('Free'), findsNWidgets(2));
    // …and no currency amount is shown for a free event.
    expect(find.textContaining('18.00'), findsNothing);
  });

  testWidgets('the search clear button carries a tooltip once a query is typed',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    // No query yet → no clear button.
    expect(find.byTooltip('Clear search'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'pilates');
    await _settle(tester);

    // The clear affordance is now an icon button with an accessible tooltip.
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });

  testWidgets('search field exposes a persistent accessible name',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: _FakeApi(const []), social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(
      find.bySemanticsLabel(RegExp('Search yoga, pilates, HIIT, run clubs')),
      findsAtLeastNWidgets(1),
    );
    handle.dispose();
  });

  testWidgets('empty results render the empty state', (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(
        find.text('No public activities match these filters yet.'),
        findsOneWidget);
  });

  testWidgets('selecting the Paid chip re-queries with paid=paid',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(api.lastArgs['paid'], isNull);

    await tester.tap(find.text('Paid'));
    await _settle(tester);
    expect(api.lastArgs['paid'], 'paid');
  });

  testWidgets('a failed search shows the error state with Retry, not empty',
      (tester) async {
    final api = _ThrowingApi();
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    expect(
        find.text(
            "Couldn't load activities. Check your connection and try again."),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // The empty state must NOT show — a failure is distinct from "no matches".
    expect(find.text('No public activities match these filters yet.'),
        findsNothing);
  });

  testWidgets('Retry after recovery clears the error and shows empty',
      (tester) async {
    final api = _ThrowingApi();
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(find.text('Retry'), findsOneWidget);

    api.failing = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);

    expect(find.text('Retry'), findsNothing);
    expect(find.text('No public activities match these filters yet.'),
        findsOneWidget);
  });

  testWidgets('selecting a category chip re-queries with that category',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    await tester.tap(find.text('Class'));
    await _settle(tester);
    expect(api.lastArgs['category'], 'class');
  });

  testWidgets('selecting the Free chip re-queries with paid=free',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);
    expect(api.lastArgs['paid'], isNull);

    // The price-filter row has its own "Free" chip (the empty-event card
    // also shows one only when a result is free — here results are empty).
    await tester.tap(find.text('Free'));
    await _settle(tester);
    expect(api.lastArgs['paid'], 'free');
  });

  testWidgets('selecting a cadence re-queries with that cadence',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    // Open the cadence dropdown and pick Weekly.
    await tester.tap(find.text('Any cadence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await _settle(tester);
    expect(api.lastArgs['cadence'], 'weekly');
  });

  testWidgets('selecting a weekday re-queries with that byday code',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    await tester.tap(find.text('Any day'));
    await tester.pumpAndSettle();
    // "Sat" is the SA byday code's label.
    await tester.tap(find.text('Sat').last);
    await _settle(tester);
    expect(api.lastArgs['byday'], 'SA');
  });

  testWidgets('selecting a time-of-day re-queries with that bucket',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    await tester.tap(find.text('Any time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning').last);
    await _settle(tester);
    expect(api.lastArgs['time'], 'morning');
  });

  testWidgets('typing a query debounces before forwarding it to the RPC',
      (tester) async {
    final api = _FakeApi(const []);
    await tester.pumpWidget(_wrap(
      DiscoverScreen(api: api, social: SocialService(), embedded: true),
    ));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'pilates');
    // Before the 250 ms debounce elapses, the query hasn't been forwarded.
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.lastArgs['query'], isNull);
    // After the debounce window it is.
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(api.lastArgs['query'], 'pilates');
  });
}
