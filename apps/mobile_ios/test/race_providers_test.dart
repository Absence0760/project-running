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

  group('a probe reports configured only on a 200', () {
    // decisions § 1073. The grader this replaced reported a readable non-429
    // 4xx as CONFIGURED, on the theory that such a status proved the function
    // ran PAST its credential gate. The theory is refuted by the endpoint
    // itself, twice, so these read the function rather than restating it.
    final fn =
        File('../backend/supabase/functions/race-results-import/index.ts')
            .readAsStringSync();

    int at(String needle) {
      final i = fn.indexOf(needle);
      expect(i, greaterThan(-1),
          reason: 'race-results-import no longer contains `$needle` — reread '
              'it and re-anchor this guard');
      return i;
    }

    test('401 is answered before any provider credential is read', () {
      // So a signed-out or expired session probes every provider and is told
      // nothing about any of them. Under the old grader a 401 was a readable
      // non-429 4xx, so it lit EVERY card as live.
      final probeBranch = at('if (isProbe) {');
      final firstUnauthorized =
          at("return Response.json({ error: 'unauthorized' }, { status: 401 })");
      expect(firstUnauthorized, lessThan(probeBranch),
          reason: 'the auth gate must precede the probe branch, or a probe '
              'could answer about a provider for an unauthenticated caller');

      // And before any PROVIDER credential — SUPABASE_URL is infrastructure the
      // client needs to check the caller at all, not an answer about a leg.
      for (final key in const [
        'RUNSIGNUP_API_KEY',
        'ULTRASIGNUP_API_KEY',
        'CHRONOTRACK_CLIENT_ID',
      ]) {
        expect(firstUnauthorized, lessThan(at(key)),
            reason: '$key is read before the caller is authenticated');
      }
    });

    test('an undispatched leg is answered 400, which the function itself '
        'introduces as "not configured"', () {
      final probeBranch = at('if (isProbe) {');
      final unknown =
          at("return Response.json({ error: 'unknown_provider' }, { status: 400 })");
      final configured = at("return Response.json({ configured: true })");
      expect(unknown, greaterThan(probeBranch));
      expect(unknown, lessThan(configured),
          reason: 'the unknown-provider refusal must be inside the probe '
              'branch, ahead of its single affirmative answer');
      // The client used to read this 400 as "configured" while the function
      // wrote it to mean the opposite — one response, two readings.
      expect(fn.contains('An unrecognised provider is not "configured"'), isTrue,
          reason: "the function's own statement of what its 400 means moved — "
              'reread it; if it now means something else, this whole grading '
              'decision needs revisiting');
    });

    test('the probe branch has exactly one affirmative answer', () {
      // Which is why "configured iff the invoke did not throw" is not a
      // simplification: `functions_client` throws for every status outside
      // 200-299, so "did not throw" IS "2xx", and the branch has one 2xx.
      final probeBranch = at('if (isProbe) {');
      final afterBranch = at("const listingId =");
      final body = fn.substring(probeBranch, afterBranch);
      expect('Response.json('.allMatches(body).length, greaterThan(1),
          reason: 're-anchor: the probe branch no longer returns responses');
      final affirmatives = RegExp(r'Response\.json\(\{ configured: true \}\)')
          .allMatches(body)
          .length;
      expect(affirmatives, 1);
      // Every other return in the branch carries an `error`.
      final errors = RegExp(r"error: '").allMatches(body).length;
      expect(errors, greaterThan(2));
    });

    test('the client grades no status at all — every throw is unavailable', () {
      // The guard that would have failed against the old code. A grader that
      // maps a status to "available" is the § 1007 defect returning; there is
      // no status this endpoint can answer that means "configured".
      final src = File('../../apps/mobile_android/lib/race_service.dart')
          .readAsStringSync();
      final sig = src.indexOf('Future<bool> isProviderConfigured(');
      expect(sig, greaterThan(-1), reason: 'isProviderConfigured moved');
      var depth = 0;
      var i = src.indexOf('{', sig);
      final open = i;
      while (i < src.length) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) break;
        }
        i++;
      }
      final body = src.substring(open, i);
      expect(body.contains('return false;'), isTrue);
      expect(body.contains('status'), isFalse,
          reason: 'isProviderConfigured inspects a status again. Only a 200 '
              'answers a probe (§ 1073) — a status-reading grader is how the '
              'phone came to report 401 and 400 as configured.');
    });
  });

  test('a probe that cannot reach Supabase answers unconfigured', () async {
    // RaceService has no Supabase behind it here, so `_c` throws a StateError
    // before any call is made. That used to answer `true` — the phone offered
    // an import leg it had never confirmed exists.
    expect(await RaceService().isProviderConfigured('runsignup'), isFalse);
    expect(await RaceService().isProviderConfigured('ultrasignup'), isFalse);
    expect(await RaceService().isProviderConfigured('chronotrack'), isFalse);
  });

  test('the leg with a refusal beyond its credential is probed on its own leg', () {
    // `race-listings-sync` gates UltraSignup on ULTRASIGNUP_API_KEY alone.
    // `race-results-import` refuses the same provider unconditionally (§ 975):
    // an athlete feed carries no race identifier, so nothing it returns can be
    // attributed to the listing a caller names. The two legs no longer agree,
    // and the tile is about the results one — probing the sync advertises an
    // import whose very next call 503s once the key is provisioned.
    final src =
        File('../backend/supabase/functions/race-results-import/index.ts')
            .readAsStringSync();
    final probeBranch = src.indexOf('if (isProbe) {');
    expect(probeBranch, greaterThan(-1),
        reason: 'race-results-import no longer has a probe branch — reread it '
            'and re-anchor this guard');
    final listingId = src.indexOf('listingId required', probeBranch);
    final branch = src.substring(probeBranch, listingId);
    expect(
      branch.contains('ultraSignUpAttributionGate()'),
      isTrue,
      reason: 'the probe branch no longer refuses UltraSignup independently of '
          'its credential. If § 975 was lifted, this guard has lost its '
          'premise — re-decide which function the tile should probe rather '
          'than deleting the assertion below',
    );
    expect(
      raceImportProviderFor('ultrasignup')!.probeFunction,
      'race-results-import',
      reason: 'the UltraSignup tile must ask the leg that would actually run',
    );
    expect(
      raceImportProviderFor('ultrasignup')!.probeBody['probe'],
      isTrue,
      reason: 'race-results-import only reports configuration in probe mode; '
          'without the flag this becomes a real import with no listing',
    );
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

  test('every leg is probed on the function that would run it', () {
    // § 1008 moved UltraSignup and left RunSignUp probing `race-listings-sync`
    // as an explicit compromise: while `race-results-import` charged a probe to
    // its 8/hour import bucket, a third probe per settings load would have cost
    // a free runner the ability to import at all. The bucket split removed the
    // reason, so no client asks the sync about a leg it does not own.
    for (final p in raceImportProviders) {
      expect(p.probeFunction, 'race-results-import', reason: p.provider);
      expect(p.probeBody['probe'], isTrue, reason: p.provider);
      expect(p.probeBody['provider'], p.provider, reason: p.provider);
    }
  });

  test('a credential probe is charged to its own bucket, not the import allowance',
      () {
    // The premise the move above rests on, read off the function rather than
    // restated: a probe reads env vars and returns, an import spends a shared
    // per-application credential and writes rows. If the two are ever collapsed
    // back onto one bucket the client change becomes the § 1008 defect again —
    // and an exhausted bucket answers 429, which is not a 200 and so reports
    // the provider unavailable (§ 1007, § 1073), making the failure silent and
    // total rather than a limit the runner can see.
    final src =
        File('../backend/supabase/functions/race-results-import/index.ts')
            .readAsStringSync();
    expect(src.contains('const denied = isProbe'), isTrue,
        reason: 'race-results-import no longer selects its bucket on the probe '
            'flag — reread it and re-anchor this guard');
    List<int> limitsFor(String bucket) {
      final m = RegExp(
        "'${RegExp.escape(bucket)}',\\s*(\\d+),\\s*(\\d+),",
      ).firstMatch(src);
      expect(m, isNotNull, reason: 'no checkRateLimitTiered call for $bucket');
      return [int.parse(m!.group(1)!), int.parse(m.group(2)!)];
    }

    final probe = limitsFor('race-results-import:probe');
    final import = limitsFor('race-results-import');
    expect(probe[0], greaterThan(import[0]),
        reason: 'the probe bucket is no more generous than the import one, so '
            'opening Settings still spends imports');
    expect(probe[1], greaterThan(import[1]),
        reason: 'the Pro probe bucket is no more generous than the import one');
  });
}
