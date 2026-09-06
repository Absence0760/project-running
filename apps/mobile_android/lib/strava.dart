import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Strava OAuth helper surface for the mobile clients. Its web counterpart
/// under `integrations/` runs the shipped flow against a browser redirect;
/// this one is unconfigured on every build today, so the two are NOT a
/// lockstep parity pair and neither registry carries them. The `strava-import` Edge Function
/// is already wired through `ApiClient.syncStrava`; this module
/// covers the *connect* half of the flow.
///
/// Today the mobile clients defer OAuth to the web (`_connectStrava`
/// in `settings_screen.dart` opens `https://threkir.com/settings/
/// integrations` in the browser). Once a native URL-scheme callback
/// lands (e.g. `threkir://strava-callback`) the connect button can
/// invoke [stravaAuthUrl] to build the authorize URL with a mobile-
/// flavoured redirect, and [completeStravaOAuth] (defined in
/// `ApiClient.completeStravaOAuth` — see api_client.dart) to exchange
/// the resulting code for a refresh token.
///
/// Gated on `STRAVA_CLIENT_ID` in `dotenv.env` so unconfigured builds
/// (every build today on mobile — the Strava developer app uses the
/// web's `PUBLIC_STRAVA_CLIENT_ID` only) report unconfigured and the
/// caller can fall back to the browser-mediated flow.

const _kEnvKey = 'STRAVA_CLIENT_ID';

/// Strava OAuth scopes — `activity:read_all` is required to see
/// non-public runs too. Mirrors the web exactly.
const _kStravaScope = 'activity:read_all,read';

/// Custom URL scheme the in-app OAuth flow listens for. Must match a
/// scheme registered in `STRAVA_ALLOWED_REDIRECTS` on the Edge Function
/// side AND a `<data android:scheme="threkir" />` intent-filter on
/// the `flutter_web_auth_2` callback activity (see AndroidManifest).
/// iOS doesn't need any Info.plist registration —
/// ASWebAuthenticationSession matches the scheme at runtime.
const String kStravaCallbackScheme = 'threkir';
const String kStravaCallbackUri = '$kStravaCallbackScheme://strava-callback';

/// Result of parsing a Strava OAuth callback URL.
///
/// Strava's `/authorize` redirects to the registered URI with either
/// (a) `?code=…&scope=…&state=…` on success or (b) `?error=access_denied`
/// when the user declines. The scope string is what the user actually
/// granted — may be a subset of what we asked for if they unchecked
/// boxes on the consent screen.
class StravaCallback {
  final String? code;
  final String? scope;
  final String? state;
  final String? error;
  const StravaCallback({this.code, this.scope, this.state, this.error});

  bool get isSuccess => code != null && code!.isNotEmpty && error == null;
}

/// Parse a `threkir://strava-callback?code=...&scope=...&state=...`
/// URL into its components. Pure helper kept out of the Settings
/// screen so the success / decline / malformed / CSRF branches can
/// be unit-tested without invoking the auth session.
StravaCallback parseStravaCallback(String url) {
  Uri? parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return const StravaCallback(error: 'invalid_url');
  }
  final q = parsed.queryParameters;
  return StravaCallback(
    code: q['code'],
    scope: q['scope'],
    state: q['state'],
    error: q['error'],
  );
}

/// Generate a fresh OAuth CSRF state token. Wraps Random.secure() for
/// 128-bit-equivalent entropy formatted as hex. RFC 6749 §10.12 only
/// requires "non-guessable" — UUID-shape would do, but Dart's
/// `crypto.randomUUID()` equivalent isn't standard library, and we
/// don't want to add a dep just for this. /audit/strava May 2026
/// Critical #1.
String mintStravaOAuthState() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// True when `STRAVA_CLIENT_ID` is present in `dotenv.env` and not the
/// `12345` placeholder. Mirrors the web's `isStravaConfigured` check.
bool isStravaConfigured({String? keyOverride}) {
  final key = keyOverride ?? dotenv.env[_kEnvKey] ?? '';
  return key.isNotEmpty && key != '12345';
}

/// Build the Strava authorization URL for [redirectUri]. The redirect
/// should match an allow-listed URI on the Strava developer console.
/// For a future mobile-native flow this will likely be a custom-scheme
/// URL the app can intercept; for now the web redirects through the
/// `/settings/integrations` page.
///
/// `approval_prompt=auto` so a user who's already authorised the app
/// gets bounced through without a second consent screen. Throws when
/// Strava isn't configured — callers gate on [isStravaConfigured]
/// first.
String stravaAuthUrl({
  required String redirectUri,
  required String state,
  String? keyOverride,
}) {
  final clientId = keyOverride ?? dotenv.env[_kEnvKey] ?? '';
  if (clientId.isEmpty || clientId == '12345') {
    throw StateError('Strava is not configured on this build');
  }
  if (state.isEmpty) {
    throw StateError('Strava state token required for CSRF guard');
  }
  final params = <String, String>{
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'approval_prompt': 'auto',
    'scope': _kStravaScope,
    'state': state,
  };
  final qs = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'https://www.strava.com/oauth/authorize?$qs';
}
