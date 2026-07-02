import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/people_screen.dart';
import '../lib/widgets/error_state.dart';

bool _supabaseReady = false;
Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

PeopleSuggestion _person({
  String id = 'p-1',
  String? name = 'Casey Marathon',
  int runs = 12,
  int sharedClubs = 1,
  bool follows = false,
}) =>
    PeopleSuggestion(
      id: id,
      displayName: name,
      publicRunsCount: runs,
      sharedClubs: sharedClubs,
      viewerFollows: follows,
    );

/// Fake people-backing ApiClient: canned suggestions + search results, and
/// counts follow / unfollow calls.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.suggestions = const [],
    this.results = const [],
    this.followShouldThrow = false,
    this.searchShouldThrow = false,
  });
  List<PeopleSuggestion> suggestions;
  List<PeopleSuggestion> results;
  bool followShouldThrow;
  bool searchShouldThrow;
  int followCalls = 0;
  int unfollowCalls = 0;
  int searchCalls = 0;
  String? lastSearchTerm;

  @override
  Future<List<PeopleSuggestion>> fetchSuggestedPeople({int limit = 12}) async =>
      suggestions;

  @override
  Future<List<PeopleSuggestion>> searchPeople(String query,
      {int limit = 20}) async {
    searchCalls++;
    lastSearchTerm = query.trim();
    if (searchShouldThrow) throw Exception('search down');
    return results;
  }

  @override
  Future<void> followUser(String targetUserId) async {
    followCalls++;
    if (followShouldThrow) throw Exception('follow down');
  }

  @override
  Future<void> unfollowUser(String targetUserId) async {
    unfollowCalls++;
  }
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('people_screen.dart — source-level structure', () {
    // The PeopleScreen mirrors apps/web/src/lib/components/SocialPeople.svelte.
    // These guards keep the search-then-suggestions wiring + the optimistic
    // follow toggle from regressing on a future refactor.
    final source =
        File('lib/screens/people_screen.dart').readAsStringSync();

    test('uses ApiClient.fetchSuggestedPeople on mount', () {
      expect(source.contains('fetchSuggestedPeople'), isTrue);
    });

    test('uses ApiClient.searchPeople for name search', () {
      expect(source.contains('searchPeople('), isTrue);
    });

    test('debounces search via a Timer (300 ms in web parity)', () {
      expect(source.contains('Duration(milliseconds: 300)'), isTrue,
          reason:
              'Matches SocialPeople.svelte\'s 300 ms debounce so a 6-char '
              'query doesn\'t fan out to 6 round-trips.');
    });

    test('optimistic follow flip with rollback on error', () {
      expect(source.contains('_flipFollow'), isTrue);
      final flips = '_flipFollow'.allMatches(source).length;
      expect(flips, greaterThanOrEqualTo(3),
          reason:
              'Expected the optimistic flip-then-rollback pattern '
              '(the helper used at least three times: declaration + '
              'forward flip + rollback flip).');
    });

    test('routes profile taps to ProfileScreen', () {
      expect(source.contains('ProfileScreen('), isTrue);
    });
  });

  group('PeopleScreen — widget behaviour', () {
    setUpAll(_ensureSupabase);

    testWidgets('suggestions render once the mount load resolves',
        (tester) async {
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: [
          _person(id: 'a', name: 'Casey Marathon'),
          _person(id: 'b', name: 'Dana Trail'),
        ]),
        embedded: true,
      )));
      await _settle(tester);
      expect(find.text('Casey Marathon'), findsOneWidget);
      expect(find.text('Dana Trail'), findsOneWidget);
    });

    testWidgets('first frame shows the suggestions loading spinner',
        (tester) async {
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: [_person()]),
        embedded: true,
      )));
      // Don't settle: the suggestions load is in flight.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty suggestions show the suggestions empty state',
        (tester) async {
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: const []),
        embedded: true,
      )));
      await _settle(tester);
      // groups_outlined is the suggestions empty glyph.
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });

    testWidgets('typing a query (debounced) runs a search and renders results',
        (tester) async {
      final api = _FakeApi(
        suggestions: const [],
        results: [_person(id: 's-1', name: 'Searched Sam')],
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'sam');
      // The 300 ms debounce must elapse before the search fires.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(api.lastSearchTerm, 'sam');
      expect(find.text('Searched Sam'), findsOneWidget);
    });

    testWidgets('a query with no matches shows the no-results empty state',
        (tester) async {
      final api = _FakeApi(suggestions: const [], results: const []);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'zzqq');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('a failed search shows a retry error state, then retry succeeds',
        (tester) async {
      final api = _FakeApi(
        suggestions: const [],
        results: [_person(id: 's-1', name: 'Recovered Rae')],
        searchShouldThrow: true,
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'rae');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      // The failure surfaces an ErrorState with a Retry button — NOT the
      // misleading "no matches" empty state.
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsNothing);
      expect(api.searchCalls, 1);

      // Retry now succeeds and renders the result.
      api.searchShouldThrow = false;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('Recovered Rae'), findsOneWidget);
      expect(api.searchCalls, 2);
    });

    testWidgets('search field exposes a persistent accessible name',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: const []),
        embedded: true,
      )));
      await _settle(tester);
      // The Semantics wrapper gives the field a name that survives once the
      // hint disappears on typing (web parity: SocialPeople's aria-label).
      expect(
        find.bySemanticsLabel(RegExp('Search runners by name')),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });

    testWidgets('tapping Follow optimistically flips the label + calls follow',
        (tester) async {
      final api = _FakeApi(suggestions: [_person(follows: false)]);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.text('Follow'), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      // Optimistic flip to "Following".
      expect(find.text('Following'), findsOneWidget);
      await _settle(tester);
      expect(api.followCalls, 1);
    });

    testWidgets('a failed follow rolls back the label + surfaces a banner',
        (tester) async {
      final api = _FakeApi(
        suggestions: [_person(follows: false)],
        followShouldThrow: true,
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      await tester.tap(find.text('Follow'));
      await _settle(tester);

      // Rollback: the label returns to "Follow" and the failure is shown.
      expect(find.text('Follow'), findsOneWidget);
      expect(api.followCalls, 1);
      await tester.pump(const Duration(seconds: 4)); // drain banner timer
    });
  });
}
