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
        () => stravaAuthUrl(redirectUri: 'runonward://strava-callback'),
        throwsA(isA<StateError>()),
      );
    });

    test('builds a Strava /oauth/authorize URL with the expected params',
        () {
      final url = stravaAuthUrl(
        redirectUri: 'runonward://strava-callback',
        keyOverride: '789012',
      );
      final parsed = Uri.parse(url);
      expect(parsed.host, 'www.strava.com');
      expect(parsed.path, '/oauth/authorize');
      expect(parsed.queryParameters['client_id'], '789012');
      expect(parsed.queryParameters['response_type'], 'code');
      expect(
        parsed.queryParameters['redirect_uri'],
        'runonward://strava-callback',
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
}
