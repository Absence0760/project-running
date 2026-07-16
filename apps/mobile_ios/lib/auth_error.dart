import 'dart:io' show SocketException;

import 'l10n/gen/app_localizations.dart';

/// Friendly, actionable categories an auth failure maps to. The raw
/// exception text (`ClientException: Failed host lookup`, a Supabase
/// `AuthApiException` toString) is developer jargon no end user should
/// read — classify it into one of these instead so the banner can tell
/// "wrong password" from "offline" from "rate-limited".
enum AuthErrorKind { offline, invalidCredentials, rateLimited, generic }

/// Classify an arbitrary auth exception. Structural / duck-typed: reads
/// the error's `code` + `statusCode` when present (Supabase's
/// `AuthException` carries both) and falls back to matching the
/// stringified message, so it works for `SocketException`, `http`'s
/// `ClientException`, and Supabase auth errors without importing them.
AuthErrorKind classifyAuthError(Object error) {
  if (error is SocketException) return AuthErrorKind.offline;

  final code = _stringProp(error, (e) => e.code)?.toLowerCase();
  final status = _statusCode(error);
  final msg = error.toString().toLowerCase();

  if (_looksOffline(msg)) return AuthErrorKind.offline;

  if (status == 429 ||
      (code != null && code.contains('rate')) ||
      code == 'over_email_send_rate_limit' ||
      code == 'over_request_rate_limit' ||
      msg.contains('rate limit') ||
      msg.contains('too many requests')) {
    return AuthErrorKind.rateLimited;
  }

  if (code == 'invalid_credentials' ||
      code == 'invalid_grant' ||
      msg.contains('invalid login credentials') ||
      msg.contains('invalid credentials')) {
    return AuthErrorKind.invalidCredentials;
  }

  return AuthErrorKind.generic;
}

/// Map an auth exception to a localized, user-facing message. Route every
/// rendered `_error =` assignment on the sign-in / sign-up screens through
/// this; keep the raw string in `debugPrint` only.
String friendlyAuthError(AppLocalizations l10n, Object error) {
  switch (classifyAuthError(error)) {
    case AuthErrorKind.offline:
      return l10n.authErrorOffline;
    case AuthErrorKind.invalidCredentials:
      return l10n.authErrorInvalidCredentials;
    case AuthErrorKind.rateLimited:
      return l10n.authErrorRateLimited;
    case AuthErrorKind.generic:
      return l10n.authErrorGeneric;
  }
}

/// Map an arbitrary exception on a non-auth form screen (club, coach, plan,
/// invite) to a localized, user-facing message. Reuses [classifyAuthError]'s
/// offline / rate-limited detection; the invalid-credentials branch can't
/// arise off the sign-in screens, so it collapses into the generic fallback.
/// Route every rendered `_error =` assignment on those screens through this
/// and keep the raw string in `debugPrint` only.
String friendlyError(AppLocalizations l10n, Object error) {
  switch (classifyAuthError(error)) {
    case AuthErrorKind.offline:
      return l10n.authErrorOffline;
    case AuthErrorKind.rateLimited:
      return l10n.authErrorRateLimited;
    case AuthErrorKind.invalidCredentials:
    case AuthErrorKind.generic:
      return l10n.authErrorGeneric;
  }
}

/// True when [error] is the data layer's signed-out rejection — the
/// `StateError('not signed in')` guard, a service's 'Not authenticated'
/// throw, a 401, or the Postgres permission failure (42501) an anon
/// request gets from an authenticated-only grant. Callers route these
/// into the shared sign-in-required state instead of a generic error +
/// a Retry that can never succeed.
bool isSignedOutError(Object error) {
  final code = _stringProp(error, (e) => e.code)?.toLowerCase();
  if (code == '42501') return true;
  if (_statusCode(error) == 401) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('not signed in') || msg.contains('not authenticated');
}

bool _looksOffline(String msg) =>
    msg.contains('failed host lookup') ||
    msg.contains('socketexception') ||
    msg.contains('clientexception') ||
    msg.contains('network is unreachable') ||
    msg.contains('connection refused') ||
    msg.contains('connection closed') ||
    msg.contains('connection reset') ||
    msg.contains('connection timed out') ||
    msg.contains('operation timed out') ||
    msg.contains('no address associated with hostname') ||
    msg.contains('handshake');

String? _stringProp(Object error, dynamic Function(dynamic) get) {
  try {
    final v = get(error as dynamic);
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

int? _statusCode(Object error) {
  try {
    final s = (error as dynamic).statusCode;
    if (s is int) return s;
    if (s is String) return int.tryParse(s);
    return null;
  } catch (_) {
    return null;
  }
}
