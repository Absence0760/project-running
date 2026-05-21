import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/strava.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('isStravaConfigured', () {
    test('false when STRAVA_CLIENT_ID is absent', () {
      expect(isStravaConfigured(), isFalse);
    });

    test('false when keyOverride is empty', () {
      expect(isStravaConfigured(keyOverride: ''), isFalse);
    });

    test('false when keyOverride is the 12345 placeholder', () {
      // Same anti-placeholder check the web uses — keeps preview
      // builds with the example value reporting as unconfigured.
      expect(isStravaConfigured(keyOverride: '12345'), isFalse);
    });

    test('true when keyOverride is a real-looking value', () {
      expect(isStravaConfigured(keyOverride: '789012'), isTrue);
    });
  });

  group('stravaAuthUrl', () {
    test('throws when Strava is not configured', () {
      expect(
        () => stravaAuthUrl(redirectUri: 'threkir://strava-callback'),
        throwsA(isA<StateError>()),
      );
    });

    test('builds a Strava /oauth/authorize URL with the expected params',
        () {
      final url = stravaAuthUrl(
        redirectUri: 'threkir://strava-callback',
        keyOverride: '789012',
      );
      final parsed = Uri.parse(url);
      expect(parsed.host, 'www.strava.com');
      expect(parsed.path, '/oauth/authorize');
      expect(parsed.queryParameters['client_id'], '789012');
      expect(parsed.queryParameters['response_type'], 'code');
      expect(
        parsed.queryParameters['redirect_uri'],
        'threkir://strava-callback',
      );
      expect(parsed.queryParameters['approval_prompt'], 'auto');
      // Web side requests "activity:read_all,read" — mobile must
      // match so the same Strava app credentials cover both clients.
      expect(parsed.queryParameters['scope'], 'activity:read_all,read');
    });

    test('URL-encodes the redirect_uri', () {
      final url = stravaAuthUrl(
        redirectUri: 'https://run.app/settings/integrations',
        keyOverride: 'cid',
      );
      // The encoded form of "https://run.app/settings/integrations"
      // must round-trip through Uri.parse.
      final parsed = Uri.parse(url);
      expect(
        parsed.queryParameters['redirect_uri'],
        'https://run.app/settings/integrations',
      );
    });
  });

  group('parseStravaCallback', () {
    test('extracts code + scope from a successful callback', () {
      final cb = parseStravaCallback(
        'threkir://strava-callback?state=&code=abc123&scope=read,activity:read_all',
      );
      expect(cb.code, 'abc123');
      expect(cb.scope, 'read,activity:read_all');
      expect(cb.error, isNull);
      expect(cb.isSuccess, isTrue);
    });

    test('flags access_denied when the user declines the consent screen', () {
      final cb = parseStravaCallback(
        'threkir://strava-callback?state=&error=access_denied',
      );
      expect(cb.code, isNull);
      expect(cb.error, 'access_denied');
      expect(cb.isSuccess, isFalse);
    });

    test('isSuccess is false when code is present but error is also set', () {
      // Strava never sends both, but the helper shouldn't paper over it
      // by treating the code as authoritative — surfacing the error is
      // safer than blindly POSTing the code to the EF.
      final cb = parseStravaCallback(
        'threkir://strava-callback?code=x&error=server_error',
      );
      expect(cb.isSuccess, isFalse);
    });

    test('handles a callback URL with no query string', () {
      final cb = parseStravaCallback('threkir://strava-callback');
      expect(cb.code, isNull);
      expect(cb.scope, isNull);
      expect(cb.error, isNull);
      expect(cb.isSuccess, isFalse);
    });

    test('exposes the constants the AndroidManifest + Strava console pin', () {
      expect(kStravaCallbackScheme, 'threkir');
      expect(kStravaCallbackUri, 'threkir://strava-callback');
    });
  });
}
