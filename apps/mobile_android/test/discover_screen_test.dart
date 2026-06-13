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
}
