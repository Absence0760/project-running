import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_auth.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('appleSignInAvailable / appleWebAuthOptions (Android)', () {
    test('fails closed when the web-auth env vars are unset', () {
      dotenv.loadFromString(envString: '', isOptional: true);
      expect(appleSignInAvailable(), isFalse);
      expect(appleWebAuthOptions(), isNull);
    });

    test('fails closed when only one env var is set', () {
      dotenv.loadFromString(
          envString: 'APPLE_SERVICE_CLIENT_ID=com.threkir.signin',
          isOptional: true);
      expect(appleSignInAvailable(), isFalse);
      expect(appleWebAuthOptions(), isNull);
    });

    test('fails closed when an env var is whitespace-only', () {
      dotenv.loadFromString(
          envString: 'APPLE_SERVICE_CLIENT_ID=com.threkir.signin\n'
              'APPLE_REDIRECT_URI=  ',
          isOptional: true);
      expect(appleSignInAvailable(), isFalse);
      expect(appleWebAuthOptions(), isNull);
    });

    test('available with options once both env vars are provisioned', () {
      dotenv.loadFromString(
          envString: 'APPLE_SERVICE_CLIENT_ID=com.threkir.signin\n'
              'APPLE_REDIRECT_URI=https://example.supabase.co/auth/v1/callback',
          isOptional: true);
      expect(appleSignInAvailable(), isTrue);
      final options = appleWebAuthOptions();
      expect(options, isNotNull);
      expect(options!.clientId, 'com.threkir.signin');
      expect(options.redirectUri,
          Uri.parse('https://example.supabase.co/auth/v1/callback'));
    });
  });

  group('iOS (native flow)', () {
    test('always available and never passes web-auth options', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      dotenv.loadFromString(envString: '', isOptional: true);
      expect(appleSignInAvailable(), isTrue);
      expect(appleWebAuthOptions(), isNull);
    });
  });
}
