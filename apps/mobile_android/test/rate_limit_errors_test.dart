// Mirror suite for the Dart port of apps/web/src/lib/rate_limit_errors.ts.
// Keep the cases byte-for-byte in lockstep with the .test.ts file.

import 'package:flutter_test/flutter_test.dart';

import '../lib/rate_limit_errors.dart';

void main() {
  group('rateLimitErrorMessage', () {
    test('returns null for null / non-P0001 / missing message inputs', () {
      expect(rateLimitErrorMessage(), isNull);
      expect(rateLimitErrorMessage(code: '23505', message: 'duplicate key'),
          isNull);
      expect(rateLimitErrorMessage(code: 'P0001'), isNull);
      expect(rateLimitErrorMessage(code: 'P0001', message: ''), isNull);
      expect(
        rateLimitErrorMessage(code: 'P0001', message: 'something unrelated'),
        isNull,
      );
    });

    test('parses create_club bucket with sub-90s wait → "X seconds"', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 42s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 42 seconds and try again.",
      );
    });

    test('parses create_route bucket with > 90s wait → rounded "X minutes"', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_route, retry in 1234s',
      );
      // 1234s → ceil(1234 / 60) = 21 minutes.
      expect(
        msg,
        "You're creating routes too quickly — please wait 21 minutes and try again.",
      );
    });

    test('exactly 90s rolls up to "2 minutes" (the cutoff)', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 90s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 2 minutes and try again.",
      );
    });

    test('89s stays as seconds (the cutoff boundary, other side)', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 89s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 89 seconds and try again.",
      );
    });

    test('1s uses singular "second"', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 1s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 1 second and try again.",
      );
    });

    test('unknown bucket falls back to generic verb', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_widget, retry in 30s',
      );
      expect(
        msg,
        "You're doing that too quickly — please wait 30 seconds and try again.",
      );
    });

    test('parses create_report bucket with "filing reports" verb', () {
      // The submit_report RPC (migration 20260908_001) delegates to
      // enforce_create_rate_limit with bucket='create_report'. Web
      // data.ts#submitReport routes through the shared helper; pin
      // the verb so a future refactor can't slip back to the old
      // "Too many reports" generic wording.
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_report, retry in 600s',
      );
      expect(
        msg,
        "You're filing reports too quickly — please wait 10 minutes and try again.",
      );
    });

    test('clone_plan_template + clone_public_plan buckets use "adopting plans"',
        () {
      // The training-plan adopt flows (clonePlanTemplate from a club
      // template, clonePublicPlan from the public library) both go
      // through enforce_create_rate_limit. Pin the shared verb.
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message: 'rate limit exceeded for clone_plan_template, retry in 300s',
        ),
        "You're adopting plans too quickly — please wait 5 minutes and try again.",
      );
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message: 'rate limit exceeded for clone_public_plan, retry in 45s',
        ),
        "You're adopting plans too quickly — please wait 45 seconds and try again.",
      );
    });

    test('clone_session_template bucket uses "adopting session plans"', () {
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message:
              'rate limit exceeded for clone_session_template, retry in 30s',
        ),
        "You're adopting session plans too quickly — please wait 30 seconds and try again.",
      );
    });

    test('clone_gym_routine_template bucket uses "adopting gym routines"', () {
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message:
              'rate limit exceeded for clone_gym_routine_template, retry in 30s',
        ),
        "You're adopting gym routines too quickly — please wait 30 seconds and try again.",
      );
    });

    test('publish_gym_routine_as_template bucket uses "publishing routines"',
        () {
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message:
              'rate limit exceeded for publish_gym_routine_as_template, retry in 120s',
        ),
        "You're publishing routines too quickly — please wait 2 minutes and try again.",
      );
    });

    test('zero seconds defaults to "a few seconds"', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 0s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait a few seconds and try again.",
      );
    });

    test('mismatched format returns null (fail safe)', () {
      expect(
        rateLimitErrorMessage(code: 'P0001', message: 'rate limit exceeded'),
        isNull,
      );
    });

    test('tolerates extra whitespace between "retry in" and the seconds', () {
      // Same edge case the web mirror covers: a future migration tweak
      // could collapse / expand whitespace around the seconds token; the
      // `\s*` keeps the parse tolerant.
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club,  retry in  42s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 42 seconds and try again.",
      );
    });

    test('parse is case-insensitive (mixed case still matches)', () {
      // Postgres' raise is case-sensitive at write-time, but case-
      // insensitive parsing guards against a future copy-edit that
      // capitalises "Rate Limit Exceeded".
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'Rate Limit Exceeded for create_club, retry in 10s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 10 seconds and try again.",
      );
    });

    test('rejects a wrong SQLSTATE even with matching message text', () {
      // Defensive: a CHECK-constraint violation (23514) or RLS deny
      // (42501) must never get the friendly-rate-limit treatment, even
      // on the hypothetical case that something else surfaces a near-
      // identical "rate limit" string. Only P0001 + matching format is
      // a match.
      expect(
        rateLimitErrorMessage(
          code: '23514',
          message: 'rate limit exceeded for create_club, retry in 42s',
        ),
        isNull,
      );
    });

    test('returns null when message has the right shape but no SQLSTATE', () {
      // A bare-string error (e.g. from a non-PostgrestException throw
      // path) must not be confused with the trigger's exception.
      expect(
        rateLimitErrorMessage(
          message: 'rate limit exceeded for create_club, retry in 42s',
        ),
        isNull,
      );
    });

    test('3540s → "59 minutes" (just-under-one-hour boundary)', () {
      // The create_club / create_route bucket window is 3600s, so
      // the trigger's `retry in` value can land anywhere in [0, 3600).
      // Pin the upper-edge wording so a rounding-logic tweak can't
      // silently regress to "59.something" or "1 hour".
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 3540s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 59 minutes and try again.",
      );
    });

    test('3600s → "60 minutes" (hour-exact boundary)', () {
      // Practically unreachable (window resets at this boundary), but
      // pinning the deterministic output keeps the helper future-proof
      // if a migration widens the window past 3600.
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club, retry in 3600s',
      );
      expect(
        msg,
        "You're creating clubs too quickly — please wait 60 minutes and try again.",
      );
    });

    test('decimal seconds in message → null (only integer matches \\d+)', () {
      // Defensive: the trigger always emits an integer; if a future
      // change inserts a decimal, fall through to the raw error.
      expect(
        rateLimitErrorMessage(
          code: 'P0001',
          message: 'rate limit exceeded for create_club, retry in 1.5s',
        ),
        isNull,
      );
    });

    test('extra trailing message text does not break the parse', () {
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_route, retry in 30s, please wait',
      );
      expect(
        msg,
        "You're creating routes too quickly — please wait 30 seconds and try again.",
      );
    });

    test('numeric chars inside the bucket name parse cleanly', () {
      // `\w+` is greedy but the trailing comma anchors the bucket
      // capture. `create_club_v2` lands as a full bucket and falls
      // through to the unknown-bucket "doing that" wording.
      final msg = rateLimitErrorMessage(
        code: 'P0001',
        message: 'rate limit exceeded for create_club_v2, retry in 30s',
      );
      expect(
        msg,
        "You're doing that too quickly — please wait 30 seconds and try again.",
      );
    });
  });
}
