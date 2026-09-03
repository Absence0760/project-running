import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('raceProbeUnavailable is fail-closed, as web already was', () {
    // Web's `isProviderNotConfigured` (core/data.ts) is the reference: only a
    // clean success or a readable non-429 4xx reports a provider live. The
    // phone answered "configured" for every one of these before, so a probe
    // that never reached the credential gate lit up a tile whose next call
    // 503s.
    test('the gate itself reads as unavailable whatever the body says', () {
      expect(
        raceProbeUnavailable(const FunctionException(
          status: 503,
          details: {'error': 'provider_not_configured'},
        )),
        isTrue,
      );
      // UltraSignup's attribution refusal is a 503 that names no credential.
      expect(
        raceProbeUnavailable(const FunctionException(
          status: 503,
          details: {
            'error': 'provider_not_configured',
            'reason': 'results_unattributable',
          },
        )),
        isTrue,
      );
      // An unreadable / unexpected 503 body is still the gate.
      expect(
        raceProbeUnavailable(const FunctionException(status: 503, details: '')),
        isTrue,
      );
    });

    test('a rate-limited or failing probe confirms nothing', () {
      for (final status in [429, 500, 502, 503, 504]) {
        expect(raceProbeUnavailable(FunctionException(status: status)), isTrue,
            reason: '$status');
      }
    });

    test('a readable non-429 4xx means the function ran past the gate', () {
      for (final status in [400, 401, 403, 404, 422]) {
        expect(raceProbeUnavailable(FunctionException(status: status)), isFalse,
            reason: '$status');
      }
    });

    test('no readable status at all is unavailable, not available', () {
      // A transport failure, Supabase not yet initialised, and a status-0
      // FunctionsFetchException on a later package version all land here.
      expect(raceProbeUnavailable(const SocketException('no route to host')),
          isTrue);
      expect(raceProbeUnavailable(StateError('not initialized')), isTrue);
      expect(raceProbeUnavailable(const FunctionException(status: 0)), isTrue);
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
    // and since § 1007 an exhausted bucket answers 429, which
    // `raceProbeUnavailable` grades as "provider unavailable", so the failure
    // would be silent and total rather than a limit the runner can see.
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
