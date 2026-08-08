import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/place_search_panel.dart';

/// The panel exists to keep the three map screens honest about the
/// distinction the dropdown used to collapse: a provider that FAILED is not
/// a place that does not exist. Before this, all three rendered
/// `if (_searchOpen && _searchResults.isNotEmpty)`, so a failed lookup — and
/// an empty one — produced no feedback at all.
Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

const _richmond = PlaceResult(name: 'Richmond, Virginia', lat: 37.54, lng: -77.43);

void main() {
  testWidgets('renders a row per result and reports the tapped one',
      (tester) async {
    PlaceResult? picked;
    await tester.pumpWidget(_host(PlaceSearchPanel(
      results: const [_richmond],
      unavailable: false,
      onSelect: (r) => picked = r,
      onRetry: () => fail('retry must not fire on the results state'),
    )));

    expect(find.text('Richmond, Virginia'), findsOneWidget);
    expect(find.byKey(const Key('place-search-empty')), findsNothing);
    expect(find.byKey(const Key('place-search-unavailable')), findsNothing);

    await tester.tap(find.text('Richmond, Virginia'));
    expect(picked, same(_richmond));
  });

  testWidgets('an empty result set says no places were found', (tester) async {
    await tester.pumpWidget(_host(PlaceSearchPanel(
      results: const [],
      unavailable: false,
      onSelect: (_) => fail('nothing to select'),
      onRetry: () => fail('retry must not fire on the empty state'),
    )));

    expect(find.byKey(const Key('place-search-empty')), findsOneWidget);
    expect(find.byKey(const Key('place-search-unavailable')), findsNothing);
  });

  testWidgets('a failed lookup says unavailable and offers a retry',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(_host(PlaceSearchPanel(
      results: const [],
      unavailable: true,
      onSelect: (_) => fail('nothing to select'),
      onRetry: () => retries++,
    )));

    expect(find.byKey(const Key('place-search-unavailable')), findsOneWidget);
    // The failure must never be dressed up as an empty result set.
    expect(find.byKey(const Key('place-search-empty')), findsNothing);

    await tester.tap(find.byType(TextButton));
    expect(retries, 1);
  });

  testWidgets('unavailable outranks a stale result list', (tester) async {
    // A retry that fails again must not fall back to showing the results of
    // the lookup before it as though they were current.
    await tester.pumpWidget(_host(PlaceSearchPanel(
      results: const [_richmond],
      unavailable: true,
      onSelect: (_) => fail('a stale result must not be selectable'),
      onRetry: () {},
    )));

    expect(find.byKey(const Key('place-search-unavailable')), findsOneWidget);
    expect(find.text('Richmond, Virginia'), findsNothing);
  });
}
