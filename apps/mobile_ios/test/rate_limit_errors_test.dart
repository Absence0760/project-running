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
  });
}
