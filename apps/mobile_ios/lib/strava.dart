import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Dart port of `apps/web/src/lib/strava.ts` — Strava OAuth helper
/// surface for the mobile clients. The `strava-import` Edge Function
/// is already wired through `ApiClient.syncStrava`; this module
/// covers the *connect* half of the flow.
///
/// Today the mobile clients defer OAuth to the web (`_connectStrava`
/// in `settings_screen.dart` opens `https://run.app/settings/
/// integrations` in the browser). Once a native URL-scheme callback
/// lands (e.g. `runonward://strava-callback`) the connect button can
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
  String? keyOverride,
}) {
  final clientId = keyOverride ?? dotenv.env[_kEnvKey] ?? '';
  if (clientId.isEmpty || clientId == '12345') {
    throw StateError('Strava is not configured on this build');
  }
  final params = <String, String>{
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'approval_prompt': 'auto',
    'scope': _kStravaScope,
  };
  final qs = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'https://www.strava.com/oauth/authorize?$qs';
}
