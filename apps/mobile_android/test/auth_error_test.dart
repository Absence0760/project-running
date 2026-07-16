import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/auth_error.dart';
import '../lib/auth_validation.dart';
import '../lib/l10n/gen/app_localizations.dart';

/// Duck-typed stand-in for a Supabase `AuthException` (carries `code`
/// + `statusCode`) so the classifier can be exercised without importing
/// the supabase auth types.
class _FakeAuthException {
  const _FakeAuthException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final String? statusCode;
  @override
  String toString() =>
      'AuthApiException(message: $message, statusCode: $statusCode, code: $code)';
}

void main() {
  group('classifyAuthError', () {
    test('SocketException → offline', () {
      expect(
        classifyAuthError(const SocketException('Failed host lookup: "x"')),
        AuthErrorKind.offline,
      );
    });

    test('ClientException "Failed host lookup" text → offline', () {
      expect(
        classifyAuthError(
            Exception('ClientException: Failed host lookup: "api.threkir.com"')),
        AuthErrorKind.offline,
      );
    });

    test('connection-refused / network-unreachable text → offline', () {
      expect(classifyAuthError(Exception('Connection refused')),
          AuthErrorKind.offline);
      expect(classifyAuthError(Exception('Network is unreachable')),
          AuthErrorKind.offline);
    });

    test('invalid_credentials code → invalidCredentials', () {
      expect(
        classifyAuthError(const _FakeAuthException('Invalid login credentials',
            code: 'invalid_credentials', statusCode: '400')),
        AuthErrorKind.invalidCredentials,
      );
    });

    test('"Invalid login credentials" message (no code) → invalidCredentials',
        () {
      expect(
        classifyAuthError(const _FakeAuthException('Invalid login credentials')),
        AuthErrorKind.invalidCredentials,
      );
    });

    test('statusCode 429 → rateLimited', () {
      expect(
        classifyAuthError(const _FakeAuthException('Too many requests',
            statusCode: '429')),
        AuthErrorKind.rateLimited,
      );
    });

    test('over_email_send_rate_limit code → rateLimited', () {
      expect(
        classifyAuthError(const _FakeAuthException(
            'For security purposes, you can only request this after 60 seconds',
            code: 'over_email_send_rate_limit')),
        AuthErrorKind.rateLimited,
      );
    });

    test('user_already_exists code → emailExists', () {
      expect(
        classifyAuthError(const _FakeAuthException('User already registered',
            code: 'user_already_exists', statusCode: '422')),
        AuthErrorKind.emailExists,
      );
    });

    test('"already registered" message (no code) → emailExists', () {
      expect(
        classifyAuthError(
            const _FakeAuthException('User already registered')),
        AuthErrorKind.emailExists,
      );
    });

    test('email_not_confirmed code → emailNotConfirmed', () {
      expect(
        classifyAuthError(const _FakeAuthException('Email not confirmed',
            code: 'email_not_confirmed', statusCode: '400')),
        AuthErrorKind.emailNotConfirmed,
      );
    });

    test('weak_password code → weakPassword', () {
      expect(
        classifyAuthError(const _FakeAuthException(
            'Password should be at least 8 characters',
            code: 'weak_password',
            statusCode: '422')),
        AuthErrorKind.weakPassword,
      );
    });

    test('"password should be at least" message (no code) → weakPassword',
        () {
      expect(
        classifyAuthError(const _FakeAuthException(
            'Password should be at least 6 characters')),
        AuthErrorKind.weakPassword,
      );
    });

    test('unrecognised error → generic', () {
      expect(classifyAuthError(Exception('boom')), AuthErrorKind.generic);
    });
  });

  testWidgets('friendlyAuthError returns the localized message per kind',
      (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const SizedBox();
      }),
    ));

    expect(friendlyAuthError(l10n, const SocketException('x')),
        l10n.authErrorOffline);
    expect(
      friendlyAuthError(
          l10n, const _FakeAuthException('', code: 'invalid_credentials')),
      l10n.authErrorInvalidCredentials,
    );
    expect(
      friendlyAuthError(l10n, const _FakeAuthException('', statusCode: '429')),
      l10n.authErrorRateLimited,
    );
    expect(
      friendlyAuthError(
          l10n, const _FakeAuthException('', code: 'user_already_exists')),
      l10n.authErrorEmailExists,
    );
    expect(
      friendlyAuthError(
          l10n, const _FakeAuthException('', code: 'email_not_confirmed')),
      l10n.authErrorEmailNotConfirmed,
    );
    expect(
      friendlyAuthError(
          l10n, const _FakeAuthException('', code: 'weak_password')),
      l10n.authErrorWeakPassword(kPasswordMinLength),
    );
    expect(friendlyAuthError(l10n, Exception('boom')), l10n.authErrorGeneric);

    // The raw jargon never appears in a rendered message.
    final rendered = friendlyAuthError(
        l10n, Exception('AuthApiException(message: nope, statusCode: 500)'));
    expect(rendered.contains('AuthApiException'), isFalse);
    expect(rendered, l10n.authErrorGeneric);
  });
}
