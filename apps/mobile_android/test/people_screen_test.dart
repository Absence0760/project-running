import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/nearby_flag.dart';
import '../lib/screens/people_screen.dart';
import '../lib/settings_destination.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/sign_in_required_state.dart';

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
  String? handle,
  String? avatarUrl,
}) =>
    PeopleSuggestion(
      id: id,
      displayName: name,
      avatarUrl: avatarUrl,
      publicRunsCount: runs,
      sharedClubs: sharedClubs,
      viewerFollows: follows,
      handle: handle,
    );

/// Fake people-backing ApiClient: canned suggestions + search results, and
/// counts follow / unfollow calls.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.suggestions = const [],
    this.results = const [],
    this.followShouldThrow = false,
    this.searchShouldThrow = false,
    this.searchError,
    this.suggestionsError,
    this.signedIn = true,
    this.nearby = const [],
  });
  List<PeopleSuggestion> suggestions;
  List<PeopleSuggestion> results;
  bool followShouldThrow;
  bool searchShouldThrow;
  Object? searchError;
  Object? suggestionsError;
  bool signedIn;
  List<NearbyRunner> nearby;
  Object? nearbyError;
  int nearbyCalls = 0;
  int followCalls = 0;
  int unfollowCalls = 0;
  int searchCalls = 0;
  int suggestionCalls = 0;
  String? lastSearchTerm;

  @override
  String? get userId => signedIn ? 'me' : null;

  @override
  Future<List<PeopleSuggestion>> fetchSuggestedPeople({int limit = 12}) async {
    suggestionCalls++;
    final err = suggestionsError;
    if (err != null) throw err;
    return suggestions;
  }

  @override
  Future<List<PeopleSuggestion>> searchPeople(String query,
      {int limit = 20}) async {
    searchCalls++;
    lastSearchTerm = query.trim();
    final err = searchError;
    if (err != null) throw err;
    if (searchShouldThrow) throw Exception('search down');
    return results;
  }

  @override
  Future<List<NearbyRunner>> fetchNearbyRunners({double radiusM = 25000}) async {
    nearbyCalls++;
    final err = nearbyError;
    if (err != null) throw err;
    return nearby;
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

NearbyRunner _nearbyRunner({
  String id = 'n-1',
  String? name = 'Nearby Nia',
  int bucket = 0,
  bool follows = false,
}) =>
    NearbyRunner(
      id: id,
      displayName: name,
      avatarUrl: null,
      bucket: bucket,
      viewerFollows: follows,
    );

/// The nearby surface is gated on a dotenv flag, so a test that wants it has to
/// turn it on explicitly — which is also what pins the default-off contract.
void _setNearbyGate(bool on) {
  if (on) {
    dotenv.env[kNearbyRunnersEnvKey] = 'true';
  } else {
    dotenv.env.remove(kNearbyRunnersEnvKey);
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

    testWidgets('an avatar whose image fails still shows the initial',
        (tester) async {
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: [
          _person(
            id: 'a',
            name: 'Casey Marathon',
            avatarUrl: 'https://example.test/casey.jpg',
          ),
        ]),
        embedded: true,
      )));
      await _settle(tester);
      // The test binding answers every HTTP request with a 400, so the
      // avatar image resolves to an error. The row must still identify
      // its person rather than rendering an empty coloured disc.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(IdentityAvatar), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });

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

    testWidgets('a suggestion with a handle renders its @handle (issue #465)',
        (tester) async {
      await tester.pumpWidget(_wrap(PeopleScreen(
        api: _FakeApi(suggestions: [
          _person(id: 'a', name: 'Casey Marathon', handle: 'caseyruns'),
        ]),
        embedded: true,
      )));
      await _settle(tester);
      expect(find.text('Casey Marathon'), findsOneWidget);
      expect(find.text('@caseyruns'), findsOneWidget);
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

  group('PeopleScreen — signed-out state (issue #224)', () {
    setUpAll(_ensureSupabase);

    testWidgets(
        'signed out (embedded) renders the sign-in state, not the search UI',
        (tester) async {
      final api = _FakeApi(signedIn: false);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(
        find.text('Sign in to search for and follow other runners.'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);
      // No search field that can only fail, and no fetch was attempted.
      expect(find.byType(TextField), findsNothing);
      expect(api.suggestionCalls, 0);
    });

    testWidgets(
        'signed out (standalone) shows a plain titled AppBar over the '
        'sign-in state', (tester) async {
      final api = _FakeApi(signedIn: false);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api)));
      await _settle(tester);

      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
        'an auth rejection mid-search routes to the sign-in state, not the '
        'retry error state', (tester) async {
      final api = _FakeApi(
        searchError: const PostgrestException(
          message: 'permission denied for function search_user_profiles',
          code: '42501',
        ),
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'sam');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      // Retrying an anon-revoked RPC can never succeed — no ErrorState.
      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets(
        'a transient suggestions failure shows a retry error state, then '
        'retry succeeds', (tester) async {
      final api = _FakeApi(
        suggestions: [_person(name: 'Recovered Rae')],
        suggestionsError: Exception('suggestions down'),
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      // A transient failure is NOT the misleading "no suggestions yet"
      // empty state, and NOT the sign-in state.
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsNothing);
      expect(find.byType(SignInRequiredState), findsNothing);

      api.suggestionsError = null;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('Recovered Rae'), findsOneWidget);
    });

    testWidgets(
        'an auth-rejected suggestions load routes to the sign-in state',
        (tester) async {
      final api = _FakeApi(
        suggestionsError: const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });
  });
  group('PeopleScreen — runners nearby (issue #466)', () {
    setUpAll(() async {
      await _ensureSupabase();
      dotenv.loadFromString(isOptional: true);
    });

    setUp(() => _setNearbyGate(false));
    tearDown(() => _setNearbyGate(false));

    testWidgets('with the gate off the surface is wholly inert', (tester) async {
      final api = _FakeApi(
        suggestions: [_person(id: 'a', name: 'Casey Marathon')],
        // A populated list the screen must never ask for.
        nearby: [_nearbyRunner()],
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      // No RPC call is the load-bearing half: person-location must not be read
      // at all before the owner + CISO/counsel sign-off flips the flag.
      expect(api.nearbyCalls, 0);
      expect(find.text('Runners nearby'), findsNothing);
      expect(find.text('Nearby Nia'), findsNothing);
      expect(find.byIcon(Icons.near_me), findsNothing);
    });

    testWidgets('with the gate on the list renders coarse buckets only',
        (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(
        suggestions: const [],
        nearby: [
          _nearbyRunner(id: 'n-1', name: 'Nearby Nia', bucket: 0),
          _nearbyRunner(id: 'n-2', name: 'Middling Mo', bucket: 2),
          _nearbyRunner(id: 'n-3', name: 'Distant Dee', bucket: 4),
        ],
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(api.nearbyCalls, 1);
      expect(find.text('Runners nearby'), findsOneWidget);
      expect(find.text('Nearby Nia'), findsOneWidget);
      // Bucket UPPER BOUNDS, formatted in the reader's unit — never the exact
      // distance, which the RPC deliberately never sends.
      expect(find.text('Within 2.00 km'), findsOneWidget);
      expect(find.text('Within 10.00 km'), findsOneWidget);
      expect(find.text('Beyond 25.00 km'), findsOneWidget);
    });

    testWidgets('an empty nearby list shows its own empty state',
        (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(suggestions: const [], nearby: const []);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.byIcon(Icons.near_me), findsOneWidget);
      expect(find.text('Nobody nearby yet'), findsOneWidget);
    });

    testWidgets('the empty state offers a real way into Preferences',
        (tester) async {
      // The tab is embedded in SocialScreen and holds neither a Preferences
      // nor a SettingsSyncService, so it names the destination and the shell
      // opens it (decisions § 710) — matching web's empty card, which links
      // to /settings/preferences. Naming the path in prose was the old
      // stand-in.
      addTearDown(() => pendingSettingsDestination.value = null);
      pendingSettingsDestination.value = null;
      _setNearbyGate(true);
      final api = _FakeApi(suggestions: const [], nearby: const []);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      final action = find.widgetWithText(OutlinedButton, 'Open Preferences');
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pump();

      expect(pendingSettingsDestination.value, SettingsDestination.preferences);
    });

    testWidgets('the empty-state body no longer recites the Settings path',
        (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(suggestions: const [], nearby: const []);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.textContaining('Settings \u2192'), findsNothing,
          reason: 'the button is the path now; reciting it as prose was the '
              'workaround for not having one');
    });

    testWidgets('with the gate off there is no Settings affordance either',
        (tester) async {
      addTearDown(() => pendingSettingsDestination.value = null);
      pendingSettingsDestination.value = null;
      final api = _FakeApi(suggestions: const [], nearby: const []);
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.text('Open Preferences'), findsNothing);
      expect(pendingSettingsDestination.value, isNull,
          reason: 'the whole surface stays inert behind the sign-off gate');
    });

    testWidgets('a failed nearby load shows a retry error state', (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(suggestions: const [], nearby: const []);
      api.nearbyError = Exception('nearby down');
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      // A failed load is not the same claim as "nobody is nearby".
      expect(find.text('Could not load runners nearby.'), findsOneWidget);
      expect(find.byIcon(Icons.near_me), findsNothing);
      expect(api.nearbyCalls, 1);

      api.nearbyError = null;
      api.nearby = [_nearbyRunner(name: 'Recovered Rae')];
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('Recovered Rae'), findsOneWidget);
      expect(api.nearbyCalls, 2);
    });

    testWidgets('following from a nearby row flips the label + calls follow',
        (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(
        suggestions: const [],
        nearby: [_nearbyRunner(follows: false)],
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);

      expect(find.text('Follow'), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      expect(find.text('Following'), findsOneWidget);
      await _settle(tester);
      expect(api.followCalls, 1);
    });

    testWidgets('an active search hides the nearby section', (tester) async {
      _setNearbyGate(true);
      final api = _FakeApi(
        suggestions: const [],
        results: [_person(id: 's-1', name: 'Searched Sam')],
        nearby: [_nearbyRunner()],
      );
      await tester.pumpWidget(_wrap(PeopleScreen(api: api, embedded: true)));
      await _settle(tester);
      expect(find.text('Runners nearby'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'sam');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Searched Sam'), findsOneWidget);
      expect(find.text('Runners nearby'), findsNothing);
      expect(find.text('Nearby Nia'), findsNothing);
    });
  });

}
