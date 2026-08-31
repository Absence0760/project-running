import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/race_service.dart';

/// The import-provider vocabulary. `race-results-import` is the third rail
/// here — the phone can only reach a leg it names, and can only name a token
/// the function accepts, so the two lists are read against each other.
void main() {
  test('every catalogue entry resolves back by its own token', () {
    for (final spec in raceImportProviders) {
      expect(raceImportProviderFor(spec.provider), same(spec));
    }
  });

  test('a listing provider with no import leg resolves to no spec', () {
    // Not gaps: parkrun / manual / raceresult listings are real rows of the
    // `race_listings.provider` CHECK that no bib-import leg exists for, and
    // `paste` is the universal manual fallback rather than a listing provider.
    for (final token in ['parkrun', 'manual', 'raceresult', 'paste', '']) {
      expect(raceImportProviderFor(token), isNull, reason: token);
    }
  });

  test('each provider carries its own fail-closed exception', () {
    // A surface showing a peer's explainer would tell a runner the wrong
    // credential is missing.
    final types = raceImportProviders.map((p) => p.unavailable.runtimeType).toSet();
    expect(types.length, raceImportProviders.length);
  });

  test('a provider with no leg is reported unconfigured without a call', () async {
    // RaceService has no Supabase behind it here, so reaching the client would
    // throw rather than answer — the null spec has to short-circuit first.
    expect(await RaceService().isProviderConfigured('parkrun'), isFalse);
  });

  test('the catalogue names exactly the tokens the Edge Function accepts', () {
    final src =
        File('../backend/supabase/functions/race-results-import/index.ts')
            .readAsStringSync();
    final m = RegExp(r'\[([^\]]*)\]\.includes\(provider\)').firstMatch(src);
    expect(m, isNotNull,
        reason: 'race-results-import no longer declares its provider vocabulary '
            'as an array literal — reread it and re-anchor this guard');
    final accepted = RegExp(r"'([a-z]+)'")
        .allMatches(m!.group(1)!)
        .map((g) => g.group(1)!)
        .toSet();
    expect(
      {...raceImportProviders.map((p) => p.provider), 'paste'},
      accepted,
      reason: 'a leg the function builds that the catalogue does not name is '
          'unreachable from the phone; a token the catalogue names that the '
          'function refuses is a 400 the runner reads as a failed import',
    );
  });
}
