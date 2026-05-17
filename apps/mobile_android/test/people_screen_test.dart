import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('people_screen.dart — source-level structure', () {
    // The PeopleScreen mirrors apps/web/src/lib/components/SocialPeople.svelte.
    // Booting the widget requires Supabase + an ApiClient configured
    // against a live stack to hydrate suggestions; the integration-test
    // gates already cover that path. These guards keep the
    // search-then-suggestions wiring + the optimistic follow toggle
    // from regressing on a future refactor.
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
      // Two flipFollow calls + a try/catch around the network call.
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
}
